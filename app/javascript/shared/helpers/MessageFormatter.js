import mila from 'markdown-it-link-attributes';
import mentionPlugin from './markdownIt/link';
import MarkdownIt from 'markdown-it';
import { parseLegacyGroupContent } from 'dashboard/helper/whatsappGroupHelper';

const setImageHeight = inlineToken => {
  const imgSrc = inlineToken.attrGet('src');
  if (!imgSrc) return;
  const url = new URL(imgSrc);
  const height = url.searchParams.get('cw_image_height');
  if (!height) return;
  inlineToken.attrSet('style', `height: ${height};`);
};

const processInlineToken = blockToken => {
  blockToken.children.forEach(inlineToken => {
    if (inlineToken.type === 'image') {
      setImageHeight(inlineToken);
    }
  });
};

const imgResizeManager = md => {
  // Custom rule for image resize in markdown
  // If the image url has a query param cw_image_height, then add a style attribute to the image
  md.core.ruler.after('inline', 'add-image-height', state => {
    state.tokens.forEach(blockToken => {
      if (blockToken.type === 'inline') {
        processInlineToken(blockToken);
      }
    });
  });
};

const createMarkdownInstance = (linkify = true) => {
  return MarkdownIt({
    html: false,
    xhtmlOut: true,
    breaks: true,
    langPrefix: 'language-',
    linkify,
    typographer: true,
    quotes: '\u201c\u201d\u2018\u2019',
    maxNesting: 20,
  })
    .use(mentionPlugin)
    .use(imgResizeManager)
    .use(mila, {
      attrs: {
        class: 'link',
        rel: 'noreferrer noopener nofollow',
        target: '_blank',
      },
    });
};

/**
 * SANEAMENTO DE EXIBIÇÃO — histórico de grupos de WhatsApp (inbox WAHA).
 *
 * Isto não conserta a origem: é maquiagem no ponto único de formatação, para o
 * histórico já gravado. A app `chatwoot` que roda dentro da WAHA concatena o
 * identificador técnico do participante ao nome e injeta tudo no corpo:
 *
 *   "👥 *Rogerio José Da Silva (229480102662169@lid)*\n\nQual Wi-Fi está?"
 *
 * Mensagens NOVAS chegam limpas (a extração acontece na ingestão, com o autor em
 * `content_attributes.group_sender`). As antigas continuam assim no banco — daí
 * este saneamento, que roda em toda superfície de uma vez (bolha, preview da
 * lista, busca, Kanban, copilot).
 *
 * Duas regras deliberadas:
 *   a) o `(...@lid)` sai SEMPRE — identificador técnico não é para ser lido;
 *   b) o `👥 Nome` FICA enquanto a mensagem for legada. Sem autor estruturado ele
 *      é a única pista de quem falou; removê-lo antes do substituto piora a vida
 *      do agente.
 *
 * DÉBITO CONHECIDO: a correção de verdade é na origem (WAHA) — ver
 * `plano/pesquisa-grupos-waha/SINTESE.md`. Enquanto ela não vier, este trecho
 * segue necessário; quando vier, ele pode ser removido junto com o helper.
 */
const sanitizeLegacyGroupContent = content => {
  // Guard barato: só mexe em texto que carrega o identificador técnico.
  if (!content || !content.includes('@lid')) return content;

  const { content: body, sender } = parseLegacyGroupContent(content);
  if (!sender?.name) return body;

  // Preserva o espaçamento original (parágrafo vs. quebra simples).
  const separator = /^👥[^\n]*\n\n/.test(content) ? '\n\n' : '\n';
  return `👥 *${sender.name}*${separator}${body}`;
};

const TWITTER_USERNAME_REGEX = /(^|[^@\w])@(\w{1,15})\b/g;
const TWITTER_USERNAME_REPLACEMENT = '$1[@$2](http://twitter.com/$2)';
const TWITTER_HASH_REGEX = /(^|\s)#(\w+)/g;
const TWITTER_HASH_REPLACEMENT = '$1[#$2](https://twitter.com/hashtag/$2)';

class MessageFormatter {
  constructor(
    message,
    isATweet = false,
    isAPrivateNote = false,
    linkify = true
  ) {
    this.message = sanitizeLegacyGroupContent(message || '');
    this.isAPrivateNote = isAPrivateNote;
    this.isATweet = isATweet;
    this.linkify = linkify;
    this.md = createMarkdownInstance(linkify);
  }

  formatMessage() {
    let updatedMessage = this.message;
    if (this.isATweet && !this.isAPrivateNote) {
      updatedMessage = updatedMessage.replace(
        TWITTER_USERNAME_REGEX,
        TWITTER_USERNAME_REPLACEMENT
      );
      updatedMessage = updatedMessage.replace(
        TWITTER_HASH_REGEX,
        TWITTER_HASH_REPLACEMENT
      );
    }
    return this.md.render(updatedMessage);
  }

  get formattedMessage() {
    return this.formatMessage();
  }

  get plainText() {
    const strippedOutHtml = new DOMParser().parseFromString(
      this.formattedMessage,
      'text/html'
    );
    return strippedOutHtml.body.textContent || '';
  }
}

export default MessageFormatter;
