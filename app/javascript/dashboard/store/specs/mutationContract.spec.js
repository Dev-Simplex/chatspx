import fs from 'fs';
import path from 'path';

// Guarda estrutural para a familia de defeito que derrubou a atribuicao de origem
// do chat de site em 20/08/2026: o recorte trouxe do upstream a action que faz
// `commit('setPendingCustomAttributes', ...)` mas NAO trouxe a mutation nem os
// campos de state. O Vuex nao lanca nesse caso — registra
// `[vuex] unknown mutation type` no console e segue — entao o dado do visitante
// (utm_source, gclid) era descartado em silencio, e nenhum teste via.
//
// Aqui a checagem e estatica: toda `commit('X')` de um `actions.js` precisa achar
// `X` no `mutations.js` irmao. Commit namespaced (`commit('mod/X', p, { root: true })`)
// resolve no modulo `mod`.

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

// tira comentario de linha e de bloco antes de varrer — scanner cego para
// comentario ja produziu diagnostico invertido neste repositorio antes
const semComentario = src =>
  src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

const mutationsDe = arquivo => {
  const src = semComentario(fs.readFileSync(arquivo, 'utf-8'));
  return new Set(
    [...src.matchAll(/^\s{2}([A-Za-z_$][\w$]*)\s*\(/gm)].map(m => m[1])
  );
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
      const src = semComentario(fs.readFileSync(mod.actions, 'utf-8'));
      const comitadas = [...src.matchAll(/commit\(\s*['"]([^'"]+)['"]/g)].map(
        m => m[1]
      );

      const ausentes = comitadas.filter(alvo => {
        const [ns, semNs] = alvo.includes('/') ? alvo.split('/') : [null, alvo];
        // namespaced: procura o mutations.js do modulo apontado; se o modulo nao
        // estiver neste conjunto, nao ha o que afirmar aqui
        const destino =
          ns === null || ns === mod.nome
            ? mod.mutations
            : modulos.find(m => m.nome === ns)?.mutations;
        if (!destino) return false;
        return !mutationsDe(destino).has(semNs);
      });

      expect(ausentes).toEqual([]);
    }
  );
});
