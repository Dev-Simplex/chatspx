/**
 * Cor default do widget na TELA de criacao de inbox.
 *
 * D11 (bloco 0.8): tem de ser o mesmo valor de
 * `Channel::WebWidget::DEFAULT_WIDGET_COLOR` (`app/models/channel/web_widget.rb`),
 * que e quem decide a cor quando a inbox nasce pela API ou pelo onboarding. As
 * duas pontas divergiam — a tela nascia verde, a API azul — e a mesma conta
 * terminava com widgets de cores diferentes conforme o caminho usado.
 *
 * A igualdade nao fica por confianca: `specs/widgetColorDefault.spec.js` le a
 * constante do arquivo Ruby e falha se os dois valores se separarem.
 */
export const DEFAULT_WIDGET_COLOR = '#2dc46f';
