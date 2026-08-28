/**
 * Fila pré-boot do SDK — bloco 1.23.
 *
 * O PROBLEMA
 *
 * `window.chatwootSDK.run()` cria o iframe e retorna na mesma linha; o app
 * dentro dele leva centenas de milissegundos para montar e começar a escutar.
 * Qualquer método de dados chamado nesse intervalo fazia `postMessage` para um
 * documento que ainda não tinha ouvinte — e a mensagem **sumia**. Sem erro, sem
 * log, sem nova tentativa. Medido em `specs/preBootQueue.spec.js`: os sete
 * saíam com `hasLoaded: false`.
 *
 * É o caso comum, não o raro: num container do GTM, a tag que chama `setUser`
 * dispara junto com a que chama `run()`.
 *
 * O QUE ESTA FILA NÃO É
 *
 * Ela **não** é a fila pré-CONVERSA. Aquela já existe, veio do upstream e vive
 * no store do painel (`conversation/actions.js`, `mutations.js`,
 * `conversationLabels.js`), tratando o caso "widget carregado, conversa ainda
 * não criada". Reimplementá-la aqui criaria DUAS filas e o atributo seria
 * enviado duas vezes (§12.1 do PLANO-MESTRE). Esta fila cobre o degrau anterior:
 * "widget ainda não carregado".
 *
 * Uma vez drenada, ela sai do caminho — `enfileirar` passa a despachar direto.
 */

const fila = [];
let drenada = false;

/**
 * Despacha agora, se o app já carregou; senão guarda para depois.
 * Devolve uma `Promise` que resolve quando a mensagem foi de fato despachada —
 * é isso que torna o contrato do SDK verificável de fora.
 */
export const enfileirar = (despachar, rotulo) => {
  if (drenada) {
    return Promise.resolve(despachar());
  }
  return new Promise((resolve, reject) => {
    fila.push({ despachar, rotulo, resolve, reject });
  });
};

/**
 * Chamado uma vez, quando o painel avisa que carregou.
 *
 * A ordem de chegada é preservada: `setUser` antes de `setLabel` continua
 * `setUser` antes de `setLabel`, porque o efeito de alguns depende do outro ter
 * acontecido (rotular um contato que ainda não foi identificado não é o mesmo
 * fato). Um item que falha **não interrompe os seguintes** — a falha vai para a
 * `Promise` daquele item, e a fila continua.
 */
export const drenar = () => {
  drenada = true;
  const pendentes = fila.splice(0, fila.length);
  pendentes.forEach(({ despachar, resolve, reject }) => {
    try {
      resolve(despachar());
    } catch (erro) {
      reject(erro);
    }
  });
  // Devolve os RÓTULOS, não a contagem: quem chama precisa saber *o que* saiu
  // para não reenviar por cima. É o que impede a segunda fila — ver o
  // comentário da re-hidratação em `IFrameHelper.events.loaded`.
  return pendentes.map(({ rotulo }) => rotulo);
};

/**
 * Os verbos que IDENTIFICAM o visitante — a lista existe porque a guarda de
 * re-hidratação precisa perguntar "a fila já cuidou da identidade?", e não "a
 * fila tinha `setUser`?".
 *
 * A primeira versão perguntava a segunda coisa (`drenados.includes('setUser')`),
 * com o rótulo cravado na comparação. `updateUser` passava por baixo: o
 * despacho grava `window.$chatwoot.user`, a re-hidratação via o objeto cheio e
 * mandava `set-user` logo depois do `update-user`. Duas identidades pelo mesmo
 * gesto — e a segunda é o verbo que SUBSTITUI o contato, o oposto do que
 * `updateUser` promete (5.17).
 *
 * Um verbo de identidade novo entra AQUI, num lugar só, e a guarda continua
 * correta sem ninguém se lembrar dela.
 */
export const VERBOS_DE_IDENTIDADE = ['setUser', 'updateUser'];

export const identidadeDrenada = (rotulos = []) =>
  rotulos.some(rotulo => VERBOS_DE_IDENTIDADE.includes(rotulo));

// Só para os testes: devolve a fila ao estado inicial entre cenários.
export const resetarFilaParaTestes = () => {
  fila.length = 0;
  drenada = false;
};

export const tamanhoDaFila = () => fila.length;
