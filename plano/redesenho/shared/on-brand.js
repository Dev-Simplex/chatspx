/* =============================================================================
   ChatSPX — Redesenho do chat de site
   on-brand.js — a cor do texto sobre a cor da marca (Task 21)

   PARA QUE SERVE
   O widget deixa o cliente escolher a cor da marca. A cor do texto por cima
   tem de ser calculada, nunca escolhida: a heurística YIQ que o widget usa
   hoje (`shared/helpers/colorHelper.js`, limiar 225; `@chatwoot/utils`, limiar
   186) diverge da WCAG em 11 de 16 cores testadas, e SEMPRE no mesmo sentido —
   escolhe branco onde o preto teria muito mais contraste [MEDIDO — 13 §3.2].
   O resultado está em produção: header verde com texto branco = 2,25:1, quando
   o preto no mesmo verde daria 9,35:1.

   COMO USAR NUM MOCKUP
     <script src="../shared/on-brand.js"><\/script>
     <script>
       // escreve --w-on-brand (e o alias --on-brand) a partir de --brand
       ChatSPXOnBrand.apply(document.documentElement, '#2dc46f');
     <\/script>

   Ou, para um escopo qualquer (dois widgets de marcas diferentes na mesma tela):
     ChatSPXOnBrand.apply(document.querySelector('.demo-inbox-b'), '#0b2545');

   EM PRODUÇÃO quem faz isso é o SERVIDOR, não o navegador: o 16 §2.5.2 prescreve
   calcular em Ruby e entregar os tokens prontos em
   `app/views/widgets/show.html.erb` — que já escreve `widgetColor` inline antes
   de qualquer bundle carregar [FATO — 15 §B7.2] — e mandar ao SDK pelo evento
   `config-set`, porque o launcher vive fora do iframe. Duplicar a fórmula em
   Ruby e em JS é risco de divergência; este arquivo é a implementação de
   referência a ser portada, e a rede de segurança enquanto isso não existe.

   RELAÇÃO COM O FALLBACK EM CSS
   `tokens.css` §3 traz a mesma fórmula em CSS puro. Ela funciona — medida por
   pixel renderizado em 8 cores, com o JS desligado — mas depende de duas
   capacidades do navegador (relative color syntax e `pow()` em `calc()`).
   Quando faltarem, `--w-on-brand` fica no default `#000000`, e para uma marca
   ESCURA isso é ilegível. Por isso: escreva o token. Não dependa do fallback.
   ============================================================================= */

(function (global) {
  'use strict';

  /* Ponto em que uma cor tem exatamente o mesmo contraste contra branco e
     contra preto puro [MEDIDO — 13 §3.2.1]. */
  var LIMIAR = 0.17913;

  function parse(color) {
    if (Array.isArray(color)) return color;
    var c = String(color).trim();

    var m = /^#([0-9a-f]{3,8})$/i.exec(c);
    if (m) {
      var h = m[1];
      if (h.length === 3 || h.length === 4) {
        h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
      }
      return [parseInt(h.slice(0, 2), 16),
              parseInt(h.slice(2, 4), 16),
              parseInt(h.slice(4, 6), 16)];
    }

    m = /^rgba?\(([^)]+)\)$/i.exec(c);
    if (m) {
      var p = m[1].split(/[\s,/]+/).filter(Boolean).slice(0, 3).map(Number);
      if (p.length === 3 && p.every(function (n) { return !isNaN(n); })) return p;
    }

    /* Qualquer outro formato (oklch, color(), nome CSS): deixa o navegador
       resolver. Fora do navegador, quem chama passa hex ou rgb. */
    if (typeof document !== 'undefined') {
      var el = document.createElement('span');
      el.style.cssText = 'position:absolute;left:-9999px;top:-9999px';
      el.style.color = c;
      document.body.appendChild(el);
      var computed = getComputedStyle(el).color;
      document.body.removeChild(el);
      var q = /(-?[\d.]+)[\s,]+(-?[\d.]+)[\s,]+(-?[\d.]+)/.exec(computed);
      if (q) {
        var scale = computed.indexOf('color(') === 0 ? 255 : 1;
        return [q[1], q[2], q[3]].map(function (n) {
          return Math.max(0, Math.min(255, Math.round(parseFloat(n) * scale)));
        });
      }
    }
    return null;
  }

  /* WCAG 2.2 — linearização por canal.
       c_lin = c/12.92                      se c ≤ 0,03928
       c_lin = ((c + 0,055)/1,055) ^ 2,4    caso contrário  */
  function linear(channel) {
    var c = channel / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  }

  /* L = 0,2126·R + 0,7152·G + 0,0722·B */
  function luminance(color) {
    var rgb = parse(color);
    if (!rgb) return null;
    return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2]);
  }

  /* (L_claro + 0,05) / (L_escuro + 0,05) */
  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b);
    if (la === null || lb === null) return null;
    if (la < lb) { var t = la; la = lb; lb = t; }
    return (la + 0.05) / (lb + 0.05);
  }

  /* A escolha. Preto PURO, não um cinza-quase-preto: com `#000000` a zona morta
     (cores em que nenhuma das duas escolhas atinge 4,5:1) é 0,00%; com
     `#111111` são 3,42% e com `#18181b`, 6,75% das cores RGB possíveis
     [MEDIDO — 13 §3.2.1, amostra de 200.000 cores]. */
  function onBrand(brand) {
    var L = luminance(brand);
    if (L === null) return '#000000';
    return L > LIMIAR ? '#000000' : '#ffffff';
  }

  /* Escreve os tokens no elemento (normalmente `document.documentElement`).
     Devolve o que foi decidido, para quem quiser exibir ou testar. */
  function apply(el, brand) {
    var target = el || document.documentElement;
    var color  = brand || getComputedStyle(target).getPropertyValue('--brand').trim();
    var on     = onBrand(color);
    var r      = contrast(color, on);

    target.style.setProperty('--brand', color);
    target.style.setProperty('--w-on-brand', on);
    target.style.setProperty('--on-brand', on);

    return {
      brand: color,
      onBrand: on,
      luminance: luminance(color),
      contrast: r,
      passesAA: r !== null && r >= 4.5
    };
  }

  /* Alias explícito para o caso ESCOPADO — mais de uma marca na mesma página.
     Custom property herda o valor COMPUTADO, não a fórmula: `--w-on-brand` é
     declarado no `:root` e derivado uma vez só, do `--brand` do `:root`. Um
     descendente que redefina apenas `--brand` herda o resultado de cima e sai
     errado. [CALIBRADO] Medido por pixel em 10 cores, nos dois temas: 6 de 10
     erradas nesse caso (todas as escuras saem pretas).

     Duas saídas, e as duas funcionam:
       1. a classe `.wui-brand-scope` do tokens.css §2.9, se você só quer CSS;
       2. esta função, se a cor vem de JS.

       ChatSPXOnBrand.setOnBrand(document.querySelector('.inbox-b'), '#0b2545'); */
  function setOnBrand(el, brand) { return apply(el, brand); }

  var api = {
    LIMIAR: LIMIAR,
    luminance: luminance,
    contrast: contrast,
    onBrand: onBrand,
    apply: apply,
    setOnBrand: setOnBrand
  };

  if (typeof module !== 'undefined' && module.exports) { module.exports = api; }
  global.ChatSPXOnBrand = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
