import { IFrameHelper } from 'widget/helpers/utils';
import i18nMessages from 'widget/i18n';

/**
 * O aviso de mensagem nova para quem NAO esta olhando (bloco 4.11 / W4.6).
 *
 * Duas coisas viajam no mesmo evento, e elas sao independentes:
 *  · o SOM, que o SDK so toca se a inbox tiver ligado (opt-in);
 *  · o TITULO da aba, que pisca sempre que a aba estiver em segundo plano.
 *
 * O texto vai daqui ja traduzido porque quem pisca e o SDK, que roda no
 * documento do site do cliente e nao carrega i18n — colocar uma tabela de
 * idiomas la dentro custaria bytes no arquivo que 100% dos visitantes baixam.
 */
const FALLBACK_LOCALE = 'en';
const ALERT_KEY = 'TITLE_FLASH_ALERT';

export const titleAlertText = (
  locale = window.chatwootWebChannel?.locale,
  messages = i18nMessages
) =>
  messages[locale]?.[ALERT_KEY] ?? messages[FALLBACK_LOCALE]?.[ALERT_KEY] ?? '';

export const playNewMessageNotificationInWidget = () => {
  IFrameHelper.sendMessage({ event: 'playAudio', title: titleAlertText() });
};
