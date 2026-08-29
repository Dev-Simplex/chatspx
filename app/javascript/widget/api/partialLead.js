import { API } from 'widget/helpers/axios';

/**
 * Bloco 4.18 — grava a resposta PARCIAL do pré-chat, antes de existir conversa.
 *
 * A sessão NÃO vai no corpo: o servidor a tira do `X-Auth-Token` (o mesmo de todo o
 * widget). Mandar a sessão daqui deixaria um cliente adulterado escrever na sessão de
 * outro visitante.
 *
 * O `website_token` NÃO É DETALHE DE TRANSPORTE
 *
 * O `X-Auth-Token` identifica a SESSÃO; o `website_token` identifica o CANAL, e é por ele
 * que o `Api::V1::Widget::BaseController` acha o widget ANTES de qualquer ação rodar
 * (`set_web_widget` → `find_by!(website_token: ...)`). Omiti-lo não produz um rascunho
 * incompleto: produz `find_by!(website_token: nil)`, que levanta `RecordNotFound` e devolve
 * 404 — e o `catch` abaixo engole o 404 sem ruído. Era esse o estado desta chamada, e o
 * efeito é o bloco inteiro: nenhuma linha em `widget_partial_leads`, nada para o varredor
 * materializar, nenhum denominador para o relatório. Medido antes da correção: 7 exemplos e
 * 5 falhas em `spec/requests/widget_partial_lead_junta_spec.rb`, todas 404 com zero linhas.
 *
 * Quem atravessa a junta agora é aquele request spec, com o corpo que
 * `specs/partialLeadJunta.spec.js` captura DESTE módulo rodando sobre o axios real. É o
 * mesmo defeito, e a mesma forma de correção, do bloco 4.21 (`approachEvent.js`).
 *
 * A chamada é deliberadamente "melhor esforço": qualquer falha é engolida, porque nenhum
 * problema em guardar o rascunho pode impedir a pessoa de continuar o pré-chat.
 */

// A mesma fonte que o resto do widget usa (`configMixin`, `telemetry.js`, `handlers.js`): o
// objeto que `app/views/widgets/show.html.erb` escreve no documento do iframe.
const tokenDoSite = () => window.chatwootWebChannel?.websiteToken;

export const savePartialLead = async ({ answers, step, stepKey }) => {
  // Sem canal a requisição está condenada ao 404 antes de sair, e requisição condenada não é
  // neutra: ela pinta o NOSSO endpoint de vermelho na aba Network do site do cliente, que é o
  // que o 2.13 existe para evitar. Mesma decisão, e pelo mesmo motivo, de `telemetry.js`.
  const websiteToken = tokenDoSite();
  if (!websiteToken) return;

  try {
    await API.post('/api/v1/widget/partial_leads', {
      website_token: websiteToken,
      answers,
      step,
      step_key: stepKey,
    });
  } catch (error) {
    // Silenciado com razão declarada: ver o comentário acima. O visitante não pode perder o
    // pré-chat porque o rascunho não gravou.
  }
};

export default { savePartialLead };
