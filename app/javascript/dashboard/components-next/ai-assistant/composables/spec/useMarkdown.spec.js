import { describe, it, expect } from 'vitest';
import { ref } from 'vue';
import { useMarkdown, renderMarkdown } from '../useMarkdown';

describe('useMarkdown — happy path', () => {
  it('renders an empty string for null/undefined refs', () => {
    expect(renderMarkdown('')).toBe('');
    expect(renderMarkdown(null)).toBe('');
    expect(renderMarkdown(undefined)).toBe('');
  });

  it('returns reactive html computed', () => {
    const text = ref('hello **world**');
    const { html } = useMarkdown(text);
    expect(html.value).toContain('<strong>world</strong>');
    text.value = 'goodbye **world**';
    expect(html.value).toContain('goodbye');
  });

  it('renders bold and italic', () => {
    expect(renderMarkdown('**bold**')).toContain('<strong>bold</strong>');
    expect(renderMarkdown('_italic_')).toContain('<em>italic</em>');
  });

  it('renders bullet and ordered lists', () => {
    const ul = renderMarkdown('- a\n- b');
    expect(ul).toContain('<ul>');
    expect(ul).toContain('<li>a</li>');
    const ol = renderMarkdown('1. a\n2. b');
    expect(ol).toContain('<ol>');
  });

  it('shifts heading levels (h1 → h3, h2 → h4)', () => {
    const h1 = renderMarkdown('# Title');
    expect(h1).toContain('<h3');
    expect(h1).not.toContain('<h1');
    const h2 = renderMarkdown('## Sub');
    expect(h2).toContain('<h4');
  });

  it('allows http(s) links and forces target=_blank rel=noopener noreferrer', () => {
    const out = renderMarkdown('[click](https://example.com)');
    expect(out).toContain('href="https://example.com"');
    expect(out).toContain('target="_blank"');
    expect(out).toContain('rel="noopener noreferrer"');
  });

  it('preserves inline code', () => {
    expect(renderMarkdown('`inline`')).toContain('<code>inline</code>');
  });
});

describe('useMarkdown — XSS hardening matrix', () => {
  it('strips raw <script> tags', () => {
    const out = renderMarkdown('hi<script>alert(1)</script>');
    expect(out).not.toContain('<script');
    expect(out).not.toContain('alert(1)');
  });

  it('strips <img onerror=…>', () => {
    const out = renderMarkdown('<img src=x onerror="alert(1)" />');
    expect(out).not.toContain('onerror');
    expect(out).not.toContain('alert(1)');
  });

  it('blocks javascript: links', () => {
    // eslint-disable-next-line no-script-url
    const out = renderMarkdown('[click](javascript:alert(1))');
    // DOMPurify drops the dangerous href entirely
    expect(out).not.toMatch(/javascript:/i);
  });

  it('blocks data: links', () => {
    const out = renderMarkdown(
      '[x](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)'
    );
    expect(out).not.toMatch(/href="data:/);
  });

  it('strips <iframe>', () => {
    const out = renderMarkdown('<iframe src="https://evil.example"></iframe>');
    expect(out).not.toContain('<iframe');
  });

  it('strips <svg onload=…>', () => {
    const out = renderMarkdown('<svg onload="alert(1)"></svg>');
    expect(out).not.toContain('<svg');
    expect(out).not.toContain('onload');
  });

  it('strips <style> blocks', () => {
    const out = renderMarkdown('<style>body{display:none}</style>visible');
    expect(out).not.toContain('<style');
    expect(out).toContain('visible');
  });

  it('blocks markdown link with javascript: scheme', () => {
    // eslint-disable-next-line no-script-url
    const out = renderMarkdown('[hi](javascript:void(0))');
    expect(out).not.toMatch(/javascript:/i);
  });

  it('strips image with onerror via reference', () => {
    const out = renderMarkdown('![alt](x onerror=alert(1))');
    // markdown-it does not produce an <img> from text without a valid URL,
    // and any inline HTML form gets sanitized away.
    expect(out).not.toContain('onerror');
  });

  it('strips <details><summary onclick=…>', () => {
    const out = renderMarkdown(
      '<details><summary onclick="alert(1)">x</summary></details>'
    );
    expect(out).not.toContain('onclick');
  });

  it('keeps allowlisted tags only (no <button>, <input>, <form>)', () => {
    const out = renderMarkdown(
      '<form><input type="text" /><button>click</button></form>'
    );
    expect(out).not.toContain('<form');
    expect(out).not.toContain('<input');
    expect(out).not.toContain('<button');
  });

  it('allowlist positive — strong, em, p, br, ul/ol/li, a, h3-h6, hr', () => {
    const out = renderMarkdown(
      '**b** _i_\n\n- one\n- two\n\n[lk](https://x.com)\n\n# H\n\n---'
    );
    expect(out).toContain('<strong>');
    expect(out).toContain('<em>');
    expect(out).toContain('<ul>');
    expect(out).toContain('<li>');
    expect(out).toContain('<a');
    expect(out).toContain('<h3');
    expect(out).toMatch(/<hr\s*\/?\s*>/);
  });

  it('handles empty / null / undefined / whitespace', () => {
    expect(renderMarkdown('')).toBe('');
    expect(renderMarkdown(null)).toBe('');
    expect(renderMarkdown(undefined)).toBe('');
    // whitespace produces an empty paragraph token; sanitized output may be
    // either '' or '<p></p>'. Either way it must not throw and must not
    // contain dangerous content.
    const out = renderMarkdown('   ');
    expect(out).not.toContain('<script');
  });
});
