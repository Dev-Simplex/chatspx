/**
 * Bloco 4.21 — A JUNTA ENTRE O CLIENTE E O SERVIDOR, medida em vez de suposta.
 *
 * O spec vizinho (`approachEvent.spec.js`) dubla `API.post` e afirma sobre o objeto que o
 * módulo entrega ao dublê. Isso mede o MÓDULO e não mede a junta: o corpo que ele congelava
 * era um corpo que o servidor recusa, e o `.catch(() => {})` do módulo engole a recusa. Foi
 * assim que os dois lados ficaram verdes — 16 exemplos no rspec, 5 no vitest — enquanto
 * nenhum evento de abordagem era gravado.
 *
 * Aqui o `API.post` é o DE VERDADE. Só o adaptador HTTP do axios é trocado, então o que este
 * spec captura é o que sairia na rede: depois do `transformRequest`, com os `params` que o
 * módulo tiver posto na query e com o corpo já serializado.
 *
 * O ARQUIVO É A JUNTA
 *
 * `spec/fixtures/widget_approach_event_wire.json` guarda essa requisição, e
 * `spec/requests/widget_approach_event_junta_spec.rb` a envia ao Rails de verdade. Os dois
 * lados ficam presos ao MESMO objeto, e a trava vale nos dois sentidos:
 *
 *   · o cliente muda e a fixture não → ESTE spec cai;
 *   · a fixture muda para algo que o servidor recusa → o request spec cai com o 404.
 *
 * Nenhum dos dois consegue ficar verde com a junta partida. Uma fixture presa de um lado só
 * é um retrato que envelhece calado, e isso não é hipótese nesta base: aconteceu com
 * `widget_brand_tokens.json`, onde 20 de 20 cores divergiam com a suíte verde
 * (ver `spec/services/widget_brand_tokens_fixture_spec.rb`).
 *
 * Para regravar depois de uma mudança deliberada no cliente:
 *
 *     ATUALIZAR_FIXTURE_JUNTA=1 npx vitest run app/javascript/widget/api/specs/approachEventJunta.spec.js
 */
import fs from 'node:fs';
import path from 'node:path';

const CAMINHO_FIXTURE = path.resolve(
  process.cwd(),
  'spec/fixtures/widget_approach_event_wire.json'
);

// O token do site é por conta, e o request spec cria a conta dele. Por isso a fixture guarda
// um SENTINELA no lugar do valor, e o Ruby troca o sentinela pelo token do canal que ele
// acabou de criar. O que a fixture fixa não é o valor — é a CHAVE e onde ela mora, que é
// exatamente a peça que faltava.
const SENTINELA_TOKEN = 'WEBSITE_TOKEN_DA_SESSAO';

// O que o host mediu e empurrou pela ponte. Nível degradado de propósito (`discreet` efetivo
// contra `bold` configurado): é o caso que separa o efeito da degradação do efeito do nível,
// e é o que o aceite do bloco cobra.
const ABORDAGEM_DO_HOST = {
  etapa: 'shown',
  approach: 'discreet',
  approach_configured: 'bold',
  ordinal: 2,
};

/** Só o que atravessa a rede. */
const naRede = config => ({
  method: config.method,
  url: config.url,
  params: config.params ?? {},
  body: JSON.parse(config.data),
});

const capturar = async (token = SENTINELA_TOKEN) => {
  vi.resetModules();
  // Não é global fabricado para o teste passar: `app/views/widgets/show.html.erb:34` escreve
  // este objeto no documento do iframe, com `websiteToken` entre as chaves, em produção.
  window.chatwootWebChannel = token ? { websiteToken: token } : {};

  const { API } = await import('widget/helpers/axios');
  const capturadas = [];
  API.defaults.adapter = config => {
    capturadas.push(naRede(config));
    return Promise.resolve({ status: 204, data: '', headers: {}, config });
  };

  const { registrarEtapaDaAbordagem, registrarConversaoDaAbordagem } =
    await import('../approachEvent');

  await registrarEtapaDaAbordagem(ABORDAGEM_DO_HOST);
  await registrarConversaoDaAbordagem();

  return capturadas;
};

describe('4.21 — a requisição REAL que o cliente põe na rede', () => {
  let requisicoes;

  beforeEach(async () => {
    requisicoes = await capturar();

    if (process.env.ATUALIZAR_FIXTURE_JUNTA) {
      const conteudo = {
        sentinel_website_token: SENTINELA_TOKEN,
        requests: requisicoes,
      };
      fs.writeFileSync(
        CAMINHO_FIXTURE,
        `${JSON.stringify(conteudo, null, 2)}\n`
      );
    }
  });

  afterEach(() => {
    delete window.chatwootWebChannel;
  });

  it('a exibição e a conversão saem — sem denominador não há medição', () => {
    expect(requisicoes.map(r => r.body.stage)).toEqual(['shown', 'converted']);
  });

  it('leva o `website_token`: sem ele o `BaseController` procura o canal por `nil` e devolve 404', () => {
    // Asserção POSITIVA de propósito. «Não manda token errado» passaria também num módulo
    // que não manda requisição nenhuma, e um bloco cujo defeito é «nada chega» não pode ser
    // guardado por uma asserção que o silêncio satisfaz.
    expect(requisicoes).not.toHaveLength(0);

    requisicoes.forEach(requisicao => {
      const naQuery = requisicao.params.website_token;
      const noCorpo = requisicao.body.website_token;
      expect(naQuery ?? noCorpo).toBe(SENTINELA_TOKEN);
    });
  });

  it('o token vem do canal, não é constante embutida no módulo', async () => {
    // Se um dia o módulo passar a mandar um valor fixo, ou a ler outra fonte, a asserção
    // acima continuaria verde — ela só compara com o que o próprio teste plantou. Trocar o
    // valor do canal e exigir que a rede acompanhe é o que separa «lê o canal» de
    // «tem um token escrito dentro».
    const outras = await capturar('OUTRO-TOKEN-DE-CANAL');

    expect(outras.map(r => r.body.website_token)).toEqual([
      'OUTRO-TOKEN-DE-CANAL',
      'OUTRO-TOKEN-DE-CANAL',
    ]);
  });

  it('sem canal no documento não sai requisição condenada ao 404', async () => {
    // O par positivo do exemplo acima. Sozinha, uma asserção de silêncio passaria também
    // num módulo que nunca manda nada — por isso ela vive ao lado das que exigem os dois
    // envios, e não sozinha.
    expect(await capturar(null)).toEqual([]);
  });

  it('é a fixture que o request spec envia ao Rails, campo a campo', () => {
    const gravada = JSON.parse(fs.readFileSync(CAMINHO_FIXTURE, 'utf8'));

    expect(gravada.sentinel_website_token).toBe(SENTINELA_TOKEN);
    expect(gravada.requests).toEqual(requisicoes);
  });
});
