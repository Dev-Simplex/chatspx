import MarkdownIt from 'markdown-it';
import mila from 'markdown-it-link-attributes';
import mentionPlugin from './markdownIt/link';
import { parseLegacyGroupContent } from 'dashboard/helper/whatsappGroupHelper';

const setImageSizing = inlineToken => {
  const imgSrc = inlineToken.attrGet('src');
  if (!imgSrc) return;
  const url = new URL(imgSrc);
  const width = url.searchParams.get('cw_image_width');
  if (width) {
    inlineToken.attrSet(
      'style',
      `width: ${width}; max-width: 100%; height: auto;`
    );
    return;
  }
  const height = url.searchParams.get('cw_image_height');
  if (height) inlineToken.attrSet('style', `height: ${height};`);
};

const processInlineToken = blockToken => {
  blockToken.children.forEach(inlineToken => {
    if (inlineToken.type === 'image') {
      setImageSizing(inlineToken);
    }
  });
};

const imgResizeManager = md => {
  // If the image URL carries a cw_image_width or cw_image_height query param,
  // add an inline style attribute so the rendered <img> respects the agent's
  // resize choice. Width takes precedence (HC drag-resize); height is kept for
  // legacy messages and the message-signature use case.
  md.core.ruler.after('inline', 'add-image-sizing', state => {
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
    .disable(['lheading'])
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

// ─────────────────────────────────────────────────────────────────────────────
// UMA INSTÂNCIA POR CONFIGURAÇÃO — bloco 2.12 (§2.2 · W2.15)
//
// Era uma instância por bolha, por render: o construtor de `MessageFormatter`
// chamava `createMarkdownInstance()`, e `createMarkdownInstance` monta um
// MarkdownIt do zero — parser, regras de core/block/inline, renderer — e ainda
// aplica três plugins (`mentionPlugin`, `imgResizeManager`, `mila`). Numa
// conversa de 40 mensagens que rerenderiza porque o agente começou a digitar,
// isso são 40 construções para produzir o mesmo HTML de antes.
//
// Compartilhar é seguro porque `md.render(src)` cria um estado próprio a cada
// chamada; o que a instância carrega é CONFIGURAÇÃO, e configuração é o que
// entra na chave deste mapa.
//
// ⚠️ POR QUE A CHAVE NÃO É SÓ `linkify`, QUE É O QUE A LINHA DO BLOCO DIZ
//
// Porque `disableImageRendering()` MUTA a instância — `md.disable([...])` e
// `md.renderer.rules.image = () => ''`. Com uma instância por bolha isso era
// local e inofensivo. Com uma instância compartilhada, a primeira chamada
// apagaria imagem de TODA superfície do SPA até o próximo reload: hoje quem
// chama é `captain/.../DocumentDetails.vue`, e o efeito apareceria depois, na
// conversa de outra tela, sem nada apontando para a causa.
//
// A prova de que o risco é real está no spec que já existia: em
// `MessageFormatter.spec.js` o caso de `#disableImageRendering` roda DEPOIS dos
// casos que esperam `<img>` renderizado. Com cache ingênuo por `linkify`, a
// ordem dos arquivos passaria a decidir o resultado.
//
// Então "sem imagem" é outra configuração, e ganha entrada própria. São no
// máximo quatro instâncias no processo inteiro; na prática, uma.
const instanciasMarkdown = new Map();

const instanciaMarkdown = (linkify, semImagens) => {
  const chave = `${linkify ? 1 : 0}|${semImagens ? 1 : 0}`;
  if (!instanciasMarkdown.has(chave)) {
    const md = createMarkdownInstance(linkify);
    if (semImagens) {
      md.disable(['add-image-sizing']);
      md.renderer.rules.image = () => '';
    }
    instanciasMarkdown.set(chave, md);
  }
  return instanciasMarkdown.get(chave);
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

// Help center article tables persist column widths as an internal
// `<!--cw-colwidths:...-->` comment before the table. It exists only for the
// editor's markdown round-trip and must never surface as text — markdown-it runs
// with `html: false`, which would otherwise escape it into a visible comment in
// rendered/plain output (e.g. dashboard search snippets). Strip the whole marker
// line, including any blockquote prefix, so a quoted table's `>` prefixes don't
// collapse together and break table parsing.
const COLWIDTHS_MARKER_REGEX =
  /^[ \t>]*<!--cw-colwidths:[\d,]+-->[ \t]*\r?\n?/gm;

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
    this.message = sanitizeLegacyGroupContent(message || '').replace(
      COLWIDTHS_MARKER_REGEX,
      ''
    );
    this.isAPrivateNote = isAPrivateNote;
    this.isATweet = isATweet;
    this.linkify = linkify;
    this.semImagens = false;
  }

  // `md` vira derivado em vez de campo: assim `disableImageRendering()` não
  // precisa desfazer nada, e nenhuma instância compartilhada é mutada.
  get md() {
    return instanciaMarkdown(this.linkify, this.semImagens);
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

  disableImageRendering() {
    this.semImagens = true;
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
