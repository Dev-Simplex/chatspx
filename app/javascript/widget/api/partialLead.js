import { API } from 'widget/helpers/axios';

/**
 * Bloco 4.18 — grava a resposta PARCIAL do pré-chat, antes de existir conversa.
 *
 * A sessão NÃO vai no corpo: o servidor a tira do `X-Auth-Token` (o mesmo de todo o
 * widget). Mandar a sessão daqui deixaria um cliente adulterado escrever na sessão de
 * outro visitante.
 *
 * A chamada é deliberadamente "melhor esforço": qualquer falha é engolida, porque
 * nenhum problema em guardar o rascunho pode impedir a pessoa de continuar o pré-chat.
 */
export const savePartialLead = async ({ answers, step, stepKey }) => {
  try {
    await API.post('/api/v1/widget/partial_leads', {
      answers,
      step,
      step_key: stepKey,
    });
  } catch (error) {
    // Silenciado com razão declarada: ver o comentário acima. O visitante não pode
    // perder o pré-chat porque o rascunho não gravou.
  }
};

export default { savePartialLead };
