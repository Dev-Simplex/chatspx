// Helpers do nó `wait_for_reply` (F2). O nó suspende o fluxo esperando a resposta do contato e
// RAMIFICA por opção: uma porta de saída por resposta esperada (`replies[].key`), mais uma porta
// de `timeout` (quando habilitado) e uma de `fallback` (sem correspondência). O acoplamento com o
// backend é EXATO (ver plano/F2-contrato-wait-for-reply.md):
//   • edge.branch === reply.key   → a opção escolhida (== o `value` da opção do send_interactive
//                                    == o id que o WhatsApp devolve na resposta interativa).
//   • edge.branch === 'timeout'   → o prazo expirou sem resposta.
//   • edge.branch AUSENTE (vazio) → fallback: resposta que não casa nenhuma porta rotulada. O
//     RunnerService (`next_node_id`) casa `edge.branch == reply_id` e, sem correspondência, cai na
//     ARESTA SEM RÓTULO — por isso a porta de fallback grava uma aresta de branch vazio.

// Fecha o loop F1→F2 sem duplicar: deriva as respostas esperadas a partir do bloco anterior
// `send_interactive`. Cada opção { title, value } vira { key: value, label: title } — o `value`
// da opção é exatamente o id que o contato devolve ao escolher, então já é a chave do ramo.
// Retorna [] se `prev` não for um send_interactive com itens (nada a pré-preencher).
export const repliesFromInteractiveNode = prev => {
  if (
    !prev ||
    prev.type !== 'action' ||
    prev.action_name !== 'send_interactive'
  ) {
    return [];
  }
  const params = Array.isArray(prev.action_params) ? prev.action_params : [];
  const first = params[0];
  const items = first && Array.isArray(first.items) ? first.items : [];
  return items
    .filter(item => item && item.value)
    .map(item => ({ key: String(item.value), label: item.title || '' }));
};

// Opções do(s) bloco(s) `send_interactive` que DESEMBOCAM neste `wait_for_reply` — a fonte da
// verdade para o campo "valor/id da resposta" no editor. O acoplamento é exato e silencioso:
// `reply.key` PRECISA ser idêntico ao `value` da opção enviada, porque é esse id que o WhatsApp
// devolve e que o RunnerService casa contra `edge.branch`. Digitado à mão, um acento ou espaço a
// mais faz a resposta certa cair no fallback. Com a lista aqui, o editor vira um select.
//
// Percorre as arestas de ENTRADA do nó (pode haver mais de uma) e junta as opções de todos os
// blocos interativos que chegam nele, deduplicando por `value` e preservando a ordem de envio.
export const interactiveOptionsForWait = (definition, nodeId) => {
  if (!definition || nodeId == null) return [];
  const nodes = Array.isArray(definition.nodes) ? definition.nodes : [];
  const edges = Array.isArray(definition.edges) ? definition.edges : [];
  const byId = new Map(nodes.map(node => [String(node.id), node]));
  const seen = new Set();
  const options = [];

  edges
    .filter(edge => String(edge.to) === String(nodeId))
    .forEach(edge => {
      repliesFromInteractiveNode(byId.get(String(edge.from))).forEach(reply => {
        if (seen.has(reply.key)) return;
        seen.add(reply.key);
        options.push(reply);
      });
    });

  return options;
};
