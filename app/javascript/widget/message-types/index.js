import TextContent from './TextContent.vue';
import EmailContent from './EmailContent.vue';
import IntegrationsContent from './IntegrationsContent.vue';
import SelectContent from './SelectContent.vue';
import FormContent from './FormContent.vue';
import CardsContent from './CardsContent.vue';
import ArticleContent from './ArticleContent.vue';
import CsatContent from './CsatContent.vue';

/**
 * Registry de `content_type` do widget.
 *
 * A chave é o valor do enum `content_type` do backend (`app/models/message.rb`).
 * Acrescentar um tipo é um arquivo novo aqui e uma linha neste mapa — nada em
 * `AgentMessageBubble.vue`, que não conhece nenhum `content_type` por nome.
 */
export const MESSAGE_TYPES = {
  text: TextContent,
  input_email: EmailContent,
  integrations: IntegrationsContent,
  input_select: SelectContent,
  form: FormContent,
  cards: CardsContent,
  article: ArticleContent,
  input_csat: CsatContent,
};

/**
 * O enum do backend tem 14 valores e o widget desenha 8. Os outros seis
 * (`input_text`, `input_textarea`, `incoming_email`, `sticker`, `input_nps`,
 * `voice_call`) e qualquer tipo futuro degradam para a bolha de texto —
 * mostrar o conteúdo em texto é correto; sumir com a mensagem não é.
 */
export const resolveMessageType = contentType =>
  MESSAGE_TYPES[contentType] || MESSAGE_TYPES.text;

/**
 * A citação de fonte (6.03) NÃO é um `content_type`: é um rodapé que vale para
 * qualquer tipo — uma resposta em cartões pode citar tanto quanto uma em texto. Por
 * isso ela sai daqui como export próprio, e não como entrada do mapa. Mora no
 * diretório do registry (e viaja no mesmo chunk) para não custar peso *eager* extra:
 * é o mesmo grafo que a bolha já carrega, com um arquivo a mais (A13).
 */
export { default as CitationList } from './CitationList.vue';
