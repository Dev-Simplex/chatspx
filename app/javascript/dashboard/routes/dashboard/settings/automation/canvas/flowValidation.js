// Validação do GRAFO antes de salvar. Existe por um incidente real: um bloco "Enviar opções"
// salvo com o corpo em branco é aceito pelo backend, mas a Meta RECUSA a mensagem
// ("The parameter interactive.body.text is required"). O menu nunca chega ao contato, e mesmo
// assim o `wait_for_reply` seguinte arma a espera — o atendente vê "menu enviado", o cliente vê
// silêncio, e a conversa morre esperando resposta a uma pergunta invisível.
//
// Duas severidades:
//   • error   → BLOQUEIA o salvamento. Campo obrigatório em branco: sempre corrigível ali mesmo,
//               sem depender de fiação no canvas.
//   • warning → pede confirmação. Buracos de fiação (saída sem conexão, chave que não casa com a
//               opção enviada) — legítimos num fluxo pela metade, mas quase sempre um esquecimento.
//
// Cada achado é { nodeId, key, severity, params } — `key` é a chave i18n; quem chama resolve o
// texto e o nome do bloco (o módulo fica livre de i18n, e assim testável).
import { repliesFromInteractiveNode } from './waitForReply';

const PREFIX = 'AUTOMATION.CANVAS.VALIDATION';
const TEXT_ACTIONS = ['send_message', 'add_private_note'];

const asArray = value => (Array.isArray(value) ? value : []);
const firstParam = node => asArray(node.action_params)[0];
const isBlank = value => !String(value ?? '').trim();

const finding = (nodeId, key, severity, params = {}) => ({
  nodeId: String(nodeId),
  key: `${PREFIX}.${key}`,
  severity,
  params,
});

// Corpo + opções do `send_interactive`. Um item sem título é descartado pelo backend
// (sanitize_interactive_items); sem nenhum título válido não há lista/botão a enviar.
const checkInteractive = (node, out) => {
  const config = firstParam(node) || {};
  if (isBlank(config.content)) {
    out.push(finding(node.id, 'INTERACTIVE_BODY_REQUIRED', 'error'));
  }
  const items = asArray(config.items).filter(item => !isBlank(item?.title));
  if (!items.length) {
    out.push(finding(node.id, 'INTERACTIVE_ITEMS_REQUIRED', 'error'));
    return;
  }
  // O `value` é o id que o WhatsApp devolve e que vira `edge.branch`. Em branco, o backend cai
  // no slug do título — e a chave do wait_for_reply, escrita à mão, deixa de casar.
  if (items.some(item => isBlank(item.value))) {
    out.push(finding(node.id, 'INTERACTIVE_VALUE_REQUIRED', 'error'));
  }
};

const checkTextAction = (node, out) => {
  if (isBlank(firstParam(node))) {
    out.push(finding(node.id, 'MESSAGE_BODY_REQUIRED', 'error'));
  }
};

// `wait_for_reply`: sem resposta esperada não há porta para onde ramificar; sem saída de
// fallback E sem timeout, qualquer resposta fora da lista encerra o run em silêncio (o walker
// não acha aresta, termina, e a resposta CERTA que vier depois é descartada).
const checkWaitForReply = (node, definition, out) => {
  const replies = asArray(node.replies);
  if (!replies.length) {
    out.push(finding(node.id, 'WAIT_REPLIES_REQUIRED', 'error'));
  }

  const outgoing = asArray(definition.edges).filter(
    edge => String(edge.from) === String(node.id)
  );
  const hasFallback = outgoing.some(edge => edge.branch == null);
  if (!hasFallback && !node.timeout?.enabled) {
    out.push(finding(node.id, 'WAIT_FALLBACK_MISSING', 'warning'));
  }

  // Chave que não existe entre as opções enviadas = porta morta: o contato escolhe, o id volta,
  // não casa nenhum branch e a resposta cai no fallback (ou no vazio).
  const offered = new Set(
    asArray(definition.edges)
      .filter(edge => String(edge.to) === String(node.id))
      .flatMap(edge =>
        repliesFromInteractiveNode(
          asArray(definition.nodes).find(
            candidate => String(candidate.id) === String(edge.from)
          )
        )
      )
      .map(reply => String(reply.key))
  );
  if (!offered.size) return;
  replies
    .filter(reply => !offered.has(String(reply.key)))
    .forEach(reply =>
      out.push(
        finding(node.id, 'WAIT_KEY_UNMATCHED', 'warning', {
          key: String(reply.key ?? ''),
        })
      )
    );
};

// Saída rotulada desenhada no nó mas sem aresta: o fluxo simplesmente para ali.
const checkDanglingBranches = (node, definition, out) => {
  const outgoing = asArray(definition.edges).filter(
    edge => String(edge.from) === String(node.id)
  );
  const connected = new Set(
    outgoing.map(edge => (edge.branch == null ? '' : String(edge.branch)))
  );
  asArray(node.replies)
    .map(reply => String(reply.key))
    .filter(key => key && !connected.has(key))
    .forEach(key =>
      out.push(finding(node.id, 'PORT_NOT_CONNECTED', 'warning', { key }))
    );
};

export const validateDefinition = definition => {
  const out = [];
  const graph = {
    nodes: asArray(definition?.nodes),
    edges: asArray(definition?.edges),
  };

  graph.nodes.forEach(node => {
    if (node.type === 'action' && node.action_name === 'send_interactive') {
      checkInteractive(node, out);
    }
    if (node.type === 'action' && TEXT_ACTIONS.includes(node.action_name)) {
      checkTextAction(node, out);
    }
    if (node.type === 'wait_for_reply') {
      checkWaitForReply(node, graph, out);
      checkDanglingBranches(node, graph, out);
    }
  });

  return out;
};

export const errorsOf = findings =>
  findings.filter(item => item.severity === 'error');
export const warningsOf = findings =>
  findings.filter(item => item.severity === 'warning');
