/**
 * QUEM CONDUZ O PRÉ-CHAT — bloco 4.02.
 *
 * `pre_chat_form_options.mode` é gravado pela tela 3.14 e validado no servidor por
 * `Channel::WebWidget::PreChatFormSchema::MODES` (`simple` | `builder` | `flow`).
 *
 *  • `simple` / `builder` → o formulário clássico do widget;
 *  • `flow`               → o pré-chat é DELEGADO ao motor de Automações, que resolve qual fluxo
 *                           de captura atende este visitante (`Flows::WidgetPrechatResolver`) e o
 *                           entrega como MENSAGENS na conversa.
 *
 * POR QUE O WIDGET PRECISA LER ISTO: o servidor só entrega o fluxo quando a inbox declara
 * `mode: 'flow'` (`widget_prechat_resolver.rb#prechat_delegated_to_flow?`), mas o widget montava
 * o formulário clássico de qualquer jeito. As duas coisas juntas são CAPTURA EM DUPLICIDADE —
 * dois pré-chats para o mesmo visitante, que é exatamente o que aquela guarda no servidor existe
 * para evitar. Esta é a outra metade dela.
 *
 * AUSÊNCIA É O ESTADO DE TODA A FROTA HOJE (a chave nasceu no 3.14 e não há backfill), e ela
 * significa "nada muda": cai no formulário clássico, que é o comportamento de sempre. Um valor
 * fora do enum cai no mesmo lugar, em vez de deixar o visitante sem pré-chat nenhum.
 *
 * A FORMA DO DADO: `window.chatwootWebChannel.preChatFormOptions` é o `pre_chat_form_options` CRU
 * do banco — `widgets/show.html.erb` e `widget/configs/create.json.jbuilder` fazem `.to_json` sem
 * camelizar — então a chave é `mode`, snake_case, dentro de um contêiner camelCase.
 */
export const PRE_CHAT_FLOW_MODE = 'flow';

/**
 * @param {object} [channel] o canal; por padrão `window.chatwootWebChannel`
 * @returns {boolean} true quando o pré-chat desta inbox é um fluxo de captura
 */
export const isPreChatDelegatedToFlow = (channel = window.chatwootWebChannel) =>
  channel?.preChatFormOptions?.mode === PRE_CHAT_FLOW_MODE;
