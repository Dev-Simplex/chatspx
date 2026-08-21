import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import i18nMessages from 'dashboard/i18n';
import FloatingVue from 'floating-vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: i18nMessages,
});

config.global.plugins = [i18n, FloatingVue];
config.global.stubs = {
  WootModal: { template: '<div><slot/></div>' },
  WootModalHeader: { template: '<div><slot/></div>' },
  NextButton: { template: '<button><slot/></button>' },
};

// O jsdom nao implementa canvas: `getContext('2d')` devolve `null`, e a primeira
// escrita do chart.js (`ctx.fillStyle = ...`) lanca ANTES do primeiro `it`. Tres
// arquivos morriam assim no carregamento e apareciam como "(0 test)" — 18 testes
// que nunca rodaram, 14 deles de autenticacao. Nao aparece como assercao vermelha,
// so como arquivo vermelho, entao passa facil por "um teste quebrado ali".
//
// Um contexto de mentira basta: nenhum desses testes verifica pixel. Se algum dia
// alguem precisar medir desenho de verdade, ai sim vale uma lib de canvas.
if (typeof HTMLCanvasElement !== 'undefined') {
  const naoFaz = () => {};
  HTMLCanvasElement.prototype.getContext = function getContext() {
    return {
      canvas: this,
      // estado que o chart.js escreve
      fillStyle: '',
      strokeStyle: '',
      lineWidth: 1,
      font: '',
      textAlign: 'start',
      textBaseline: 'alphabetic',
      globalAlpha: 1,
      globalCompositeOperation: 'source-over',
      lineCap: 'butt',
      lineJoin: 'miter',
      miterLimit: 10,
      shadowBlur: 0,
      shadowColor: 'rgba(0, 0, 0, 0)',
      shadowOffsetX: 0,
      shadowOffsetY: 0,
      // metodos que ele chama
      save: naoFaz,
      restore: naoFaz,
      beginPath: naoFaz,
      closePath: naoFaz,
      clip: naoFaz,
      fill: naoFaz,
      stroke: naoFaz,
      moveTo: naoFaz,
      lineTo: naoFaz,
      arc: naoFaz,
      arcTo: naoFaz,
      bezierCurveTo: naoFaz,
      quadraticCurveTo: naoFaz,
      rect: naoFaz,
      fillRect: naoFaz,
      strokeRect: naoFaz,
      clearRect: naoFaz,
      fillText: naoFaz,
      strokeText: naoFaz,
      translate: naoFaz,
      rotate: naoFaz,
      scale: naoFaz,
      transform: naoFaz,
      setTransform: naoFaz,
      resetTransform: naoFaz,
      setLineDash: naoFaz,
      getLineDash: () => [],
      drawImage: naoFaz,
      putImageData: naoFaz,
      createLinearGradient: () => ({ addColorStop: naoFaz }),
      createRadialGradient: () => ({ addColorStop: naoFaz }),
      createPattern: () => null,
      measureText: texto => ({ width: String(texto ?? '').length * 6 }),
      getImageData: (_x, _y, w = 1, h = 1) => ({
        data: new Uint8ClampedArray(Math.max(1, w * h * 4)),
        width: w,
        height: h,
      }),
    };
  };
}
