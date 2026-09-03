import fs from 'fs';
import path from 'path';

// Guarda estrutural para a familia de defeito que derrubou a atribuicao de origem
// do chat de site em 20/08/2026: o recorte trouxe do upstream a action que faz
// `commit('setPendingCustomAttributes', ...)` mas NAO trouxe a mutation nem os
// campos de state. O Vuex nao lanca nesse caso — registra
// `[vuex] unknown mutation type` no console e segue — entao o dado do visitante
// (utm_source, gclid) era descartado em silencio, e nenhum teste via.
//
// Tres formas convivem no repo, e cobrir so uma faz o guarda passar no VACUO:
//   a) literal    -> `commit('setX')`                    + `setX($state) {}`
//   b) computado  -> `commit(types.SET_X)`               + `[types.SET_X]($state) {}`
//   c) de raiz    -> `commit(types.X, p, {root: true})`  + definida em QUALQUER modulo
//                    (o modulo `conversations` define as dele no proprio index.js)
// O ultimo exemplo do arquivo existe para provar que a checagem nao afirma vazio.

const RAIZ = path.resolve(process.cwd(), 'app/javascript');

const acha = (dir, nome, encontrados = []) => {
  for (const entrada of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entrada.name);
    if (entrada.isDirectory()) {
      if (['node_modules', 'specs', 'spec'].includes(entrada.name)) continue;
      acha(p, nome, encontrados);
    } else if (entrada.name === nome) {
      encontrados.push(p);
    }
  }
  return encontrados;
};

// comentario cega scanner: ja produziu diagnostico invertido neste repositorio
const semComentario = src =>
  src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

// aceita `nome(`, `nome:`, `async nome(` e `[ns.NOME]`
const nomesDefinidos = arquivo => {
  const src = semComentario(fs.readFileSync(arquivo, 'utf-8'));
  const nomes = new Set();
  for (const m of src.matchAll(
    /^\s{2}(?:async\s+)?([A-Za-z_$][\w$]*)\s*[:(]/gm
  )) {
    nomes.add(m[1]);
  }
  for (const m of src.matchAll(/^\s{2}\[\s*(?:[\w$]+\.)?([\w$]+)\s*\]/gm)) {
    nomes.add(m[1]);
  }
  return nomes;
};

const comitados = arquivo => {
  const src = semComentario(fs.readFileSync(arquivo, 'utf-8'));
  const alvos = [];
  // a chamada inteira, para saber se leva `{ root: true }`
  for (const m of src.matchAll(/commit\(([\s\S]{0,220}?)\);/g)) {
    const chamada = m[1];
    const raiz = /root\s*:\s*true/.test(chamada);
    const primeiro = chamada.split(',')[0];
    for (const lit of primeiro.matchAll(/['"]([^'"]+)['"]/g)) {
      alvos.push({ nome: lit[1], raiz });
    }
    for (const id of primeiro.matchAll(
      /(?:^|[\s?:(])(?:[\w$]+\.)?([A-Z][A-Z0-9_]{2,})\b/g
    )) {
      alvos.push({ nome: id[1], raiz });
    }
  }
  return alvos;
};

let universoCache = null;
const universoDeMutations = () => {
  if (universoCache) return universoCache;
  universoCache = new Set();
  const dentroDeModulos = `${path.sep}store${path.sep}modules${path.sep}`;
  for (const nome of ['mutations.js', 'index.js']) {
    for (const arq of acha(RAIZ, nome)) {
      if (!arq.includes(dentroDeModulos)) continue;
      for (const n of nomesDefinidos(arq)) universoCache.add(n);
    }
  }
  return universoCache;
};

const modulos = acha(RAIZ, 'actions.js')
  .filter(a => fs.existsSync(path.join(path.dirname(a), 'mutations.js')))
  .map(a => ({
    nome: path.basename(path.dirname(a)),
    actions: a,
    mutations: path.join(path.dirname(a), 'mutations.js'),
  }));

describe('contrato entre actions e mutations dos modulos vuex', () => {
  it('encontra os modulos que tem actions.js e mutations.js irmaos', () => {
    expect(modulos.length).toBeGreaterThan(0);
  });

  it.each(modulos.map(m => [m.nome, m]))(
    '%s: toda mutation comitada existe',
    (_nome, mod) => {
      const definidasAqui = nomesDefinidos(mod.mutations);
      const ausentes = comitados(mod.actions)
        .filter(({ nome, raiz }) => {
          const [ns, semNs] = nome.includes('/')
            ? nome.split('/')
            : [null, nome];
          // `{ root: true }` sem prefixo mira mutation de RAIZ, que pode estar
          // registrada por qualquer modulo — inclusive dentro de um index.js
          if (raiz && ns === null) return !universoDeMutations().has(semNs);
          const destino =
            ns === null || ns === mod.nome
              ? mod.mutations
              : modulos.find(m => m.nome === ns)?.mutations;
          if (!destino) return false;
          const nomes =
            destino === mod.mutations ? definidasAqui : nomesDefinidos(destino);
          return !nomes.has(semNs);
        })
        .map(x => x.nome);
      expect([...new Set(ausentes)]).toEqual([]);
    }
  );

  // sem isto, um modulo cujo estilo o extrator nao entende passa afirmando NADA
  it('nao passa no vacuo: cada modulo tem commits e mutations reconhecidos', () => {
    const vazios = modulos
      .map(m => ({
        nome: m.nome,
        commits: new Set(comitados(m.actions).map(x => x.nome)).size,
        mutations: nomesDefinidos(m.mutations).size,
      }))
      .filter(x => x.commits === 0 || x.mutations === 0);
    expect(vazios).toEqual([]);
  });
});
