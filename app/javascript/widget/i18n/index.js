/**
 * Traduções do widget — carregadas SOB DEMANDA (bloco 2.18).
 *
 * O arquivo anterior tinha 41 `import` estáticos de JSON, um por idioma. Import
 * estático é first-paint: cada visitante baixava as 41 traduções para ler UMA.
 * Medido no grafo de produção: 213.027 B crus só de locale, ~9,4% do fecho
 * eager do widget.
 *
 * O `en` continua estático de propósito — ele é o fallback do vue-i18n, e um
 * fallback que chega pela rede tarde demais não é fallback. Os outros 40 viram
 * um chunk cada, e o boot busca UM: `entrypoints/widget.js` espera
 * `carregarLocale()` antes de montar, para que o primeiro render já saia no
 * idioma certo em vez de piscar em inglês.
 *
 * `mensagens` é o MESMO objeto do começo ao fim, e é por isso que ele é mutado
 * em vez de recriado: `WidgetAudioNotificationHelper` o recebe como valor
 * padrão de parâmetro, e uma troca de referência o deixaria lendo uma tabela
 * congelada no boot.
 */
import en from './locale/en.json';

// `import.meta.glob` sem `eager`: o Vite emite um chunk por arquivo e devolve
// aqui um mapa de funções que os buscam. Nenhum deles entra no fecho estático.
const carregadores = import.meta.glob('./locale/*.json');

export const mensagens = { en };

export const carregarLocale = async codigo => {
  if (!codigo) return undefined;
  if (mensagens[codigo]) return mensagens[codigo];
  const carregar = carregadores[`./locale/${codigo}.json`];
  // Código desconhecido não é erro: o widget cai no fallback `en`, que é o
  // mesmo comportamento de antes para um idioma que não existisse na tabela.
  if (!carregar) return undefined;
  const modulo = await carregar();
  mensagens[codigo] = modulo.default ?? modulo;
  return mensagens[codigo];
};

export default mensagens;
