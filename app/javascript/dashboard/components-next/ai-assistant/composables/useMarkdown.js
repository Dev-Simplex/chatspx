import { computed } from 'vue';
import MarkdownIt from 'markdown-it';
import markdownItLinkAttributes from 'markdown-it-link-attributes';
import DOMPurify from 'dompurify';

/**
 * Markdown rendering pipeline for the AI Assistant panel.
 *
 * The renderer is intentionally conservative: it disables raw HTML in the
 * source (`html: false`), forces external links to open in a new tab with
 * `noopener noreferrer`, and shifts headings down two levels so an LLM-
 * generated `# Title` cannot collide with the surrounding page hierarchy
 * (we never render `h1`/`h2` inside a chat bubble).
 *
 * After rendering, the HTML is sanitized with a hardened DOMPurify config
 * that allowlists only the small set of tags/attributes Captain responses
 * realistically produce. Anything outside the list (script, iframe, on*
 * handlers, javascript: URLs, etc.) is dropped.
 */

const md = new MarkdownIt({
  html: false,
  linkify: true,
  breaks: true,
});

// Reject dangerous link schemes at parse time so markdown-it never produces
// an <a href="javascript:…"> in the first place — the sanitizer is a second
// layer of defense, not the only one.
const SAFE_LINK_RE = /^(https?:\/\/|mailto:|tel:|\/|#|\?)/i;
md.validateLink = url => {
  if (!url) return false;
  return SAFE_LINK_RE.test(String(url).trim());
};

md.use(markdownItLinkAttributes, {
  matcher(href) {
    return /^https?:\/\//.test(href);
  },
  attrs: {
    target: '_blank',
    rel: 'noopener noreferrer',
  },
});

// Headings start at h3 inside chat bubbles — h1 collapses to h3, h2 → h4, etc.
md.renderer.rules.heading_open = (tokens, idx) => {
  const tag = tokens[idx].tag;
  const level = parseInt(tag.replace('h', ''), 10);
  const newLevel = Math.min(level + 2, 6);
  return `<h${newLevel} class="font-semibold mt-2 mb-1">`;
};
md.renderer.rules.heading_close = (tokens, idx) => {
  const tag = tokens[idx].tag;
  const level = parseInt(tag.replace('h', ''), 10);
  const newLevel = Math.min(level + 2, 6);
  return `</h${newLevel}>`;
};

const PURIFY_CONFIG = {
  ALLOWED_TAGS: [
    'p',
    'br',
    'strong',
    'em',
    'code',
    'pre',
    'blockquote',
    'ul',
    'ol',
    'li',
    'a',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    // Tabelas: o modelo gera comparativo o tempo todo ("opção A × opção B").
    // Sem estas tags o DOMPurify descartava a linha de cabeçalho inteira e
    // colava as células numa frase só — pior que perder a informação, porque
    // vantagem de uma ação virava desvantagem da outra na tela de quem atende.
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
  ],
  ALLOWED_ATTR: ['href', 'target', 'rel', 'class'],
  FORBID_TAGS: [
    'script',
    'style',
    'iframe',
    'svg',
    'math',
    'form',
    'input',
    'button',
    'object',
    'embed',
    'link',
  ],
  FORBID_ATTR: [
    'onerror',
    'onclick',
    'onload',
    'onmouseover',
    'onfocus',
    'onblur',
    'onkeydown',
    'onkeyup',
    'onkeypress',
  ],
};

// Defense-in-depth: even after markdown-it escapes raw HTML and DOMPurify
// strips disallowed tags, payloads such as `<svg onload="alert(1)">` survive
// as escaped text (e.g. `&lt;svg onload="…"&gt;`). The sanitizer correctly
// considers this safe (it is text, not markup), but the literal substrings
// `onerror`, `onload`, `onclick`, `<script`, `<svg`, `javascript:`, `data:`
// inside markdown that LLMs occasionally echo back are noise we never want
// to render anyway. Strip them after sanitization.
const NOISE_PATTERNS = [
  /&lt;script[^&]*?&gt;.*?(?:&lt;\/script&gt;|$)/gi,
  /&lt;svg[^&]*?&gt;.*?(?:&lt;\/svg&gt;|$)/gi,
  /&lt;iframe[^&]*?&gt;.*?(?:&lt;\/iframe&gt;|$)/gi,
  /&lt;style[^&]*?&gt;.*?(?:&lt;\/style&gt;|$)/gi,
  /&lt;details[^&]*?&gt;.*?(?:&lt;\/details&gt;|$)/gi,
  /&lt;form[^&]*?&gt;.*?(?:&lt;\/form&gt;|$)/gi,
  /\bon[a-z]+\s*=\s*(?:&quot;[^&]*&quot;|&#39;[^&]*&#39;|"[^"]*"|'[^']*'|[^\s>]+)/gi,
  // Markdown links/images that markdown-it left as literal text after the
  // url scheme was rejected (e.g. `[hi](javascript:…)` or `![alt](x onerror=…)`)
  /\[[^\]]*\]\(\s*javascript:[^)]*\)/gi,
  /\[[^\]]*\]\(\s*data:[^)]*\)/gi,
  /!\[[^\]]*\]\([^)]*\bon[a-z]+\s*=[^)]*\)/gi,
];

function stripResidualNoise(html) {
  let out = html;
  NOISE_PATTERNS.forEach(re => {
    out = out.replace(re, '');
  });
  return out;
}

/**
 * Returns a reactive `html` ref derived from `textRef`. The output is already
 * sanitized — callers can safely render it with `v-html`.
 *
 * @param {import('vue').Ref<string>|{ value: string }} textRef
 * @returns {{ html: import('vue').ComputedRef<string> }}
 */
export function useMarkdown(textRef) {
  const html = computed(() => {
    const text = textRef?.value ?? '';
    if (!text) return '';
    const rendered = md.render(text);
    const sanitized = DOMPurify.sanitize(rendered, PURIFY_CONFIG);
    return stripResidualNoise(sanitized);
  });
  return { html };
}

// Exported for tests / advanced callers that want one-shot rendering
// without mounting a Vue component.
export function renderMarkdown(text) {
  if (!text) return '';
  const sanitized = DOMPurify.sanitize(md.render(text), PURIFY_CONFIG);
  return stripResidualNoise(sanitized);
}
