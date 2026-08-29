/**
 * Bloco 4.18 — A JUNTA ENTRE O CLIENTE E O SERVIDOR do lead incompleto.
 *
 * O spec de tela (`components/PreChat/specs/partialLead.spec.js`) dubla o módulo inteiro
 * (`vi.mock('widget/api/partialLead')`) e afirma sobre os ARGUMENTOS da chamada; o rspec do
 * controller monta o corpo à mão. Cada lado prova o seu lado e o corpo que sai do navegador
 * nunca encosta no Rails — foi exatamente assim que o bloco 4.21 ficou com 21 exemplos
 * verdes e ZERO evento gravado em produção, e o diagnóstico daquele bloco já apontava este
 * arquivo como portador do mesmo defeito.
 *
 * Aqui o `API.post` é o DE VERDADE: só o adaptador HTTP do axios é trocado, então o que este
 * spec captura é o que sairia na rede.
 *
 * O ARQUIVO É A JUNTA
 *
 * `spec/fixtures/widget_partial_lead_wire.json` guarda essa requisição e
 * `spec/requests/widget_partial_lead_junta_spec.rb` a envia ao Rails de verdade. A trava vale
 * nos dois sentidos: cliente muda e a fixture não, ESTE spec cai; a fixture muda para algo que
 * o servidor recusa, o request spec cai com 404 e nenhuma linha gravada. Fixture presa de um
 * lado só é retrato que envelhece calado — já aconteceu nesta base com
 * `widget_brand_tokens.json` (20 de 20 cores divergindo, suíte verde).
 *
 * Para regravar depois de uma mudança deliberada no cliente:
 *
 *     ATUALIZAR_FIXTURE_JUNTA=1 npx vitest run app/javascript/widget/api/specs/partialLeadJunta.spec.js
 */
import fs from 'node:fs';
import path from 'node:path';

const CAMINHO_FIXTURE = path.resolve(
  process.cwd(),
  'spec/fixtures/widget_partial_lead_wire.json'
);

// O token do site é por conta e o request spec cria a conta dele; a fixture guarda um
// SENTINELA no lugar do valor e o Ruby troca pelo token do canal que acabou de criar. O que a
// fixture fixa não é o valor — é a CHAVE e onde ela mora, que é a peça que faltava.
const SENTINELA_TOKEN = 'WEBSITE_TOKEN_DA_SESSAO';

// O caso do aceite, em dados: nome e e-mail respondidos, abandono no terceiro campo.
const RASCUNHO = {
  answers: { fullName: 'Walisson', emailAddress: 'walisson@empresa.com.br' },
  step: 3,
  stepKey: 'phoneNumber',
};

/** Só o que atravessa a rede. */
const naRede = config => ({
  method: config.method,
  url: config.url,
  params: config.params ?? {},
  body: JSON.parse(config.data),
});

// O módulo e o axios são importados UMA vez: `partialLead.js` não guarda estado entre
// chamadas (o token é lido do documento a cada envio), então reimportar a cada caso só
// acrescentaria segundos de transform — e foi o que fez este arquivo estourar o timeout de 5 s
// quando rodou junto com os outros seis.
const capturadas = [];
let savePartialLead;

beforeAll(async () => {
  const { API } = await import('widget/helpers/axios');
  API.defaults.adapter = config => {
    capturadas.push(naRede(config));
    return Promise.resolve({ status: 200, data: '', headers: {}, config });
  };
  ({ savePartialLead } = await import('../partialLead'));
});

const capturar = async (token = SENTINELA_TOKEN) => {
  capturadas.length = 0;
  // Não é global fabricado para o teste passar: `app/views/widgets/show.html.erb` escreve este
  // objeto no documento do iframe, com `websiteToken` entre as chaves, em produção.
  window.chatwootWebChannel = token ? { websiteToken: token } : {};

  await savePartialLead(RASCUNHO);

  return [...capturadas];
};

describe('4.18 — a requisição REAL que o cliente põe na rede', () => {
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

  it('o rascunho sai, com as respostas e a etapa em que a pessoa parou', () => {
    expect(requisicoes).toHaveLength(1);
    expect(requisicoes[0].url).toBe('/api/v1/widget/partial_leads');
    expect(requisicoes[0].body.answers).toEqual(RASCUNHO.answers);
    expect(requisicoes[0].body.step).toBe(3);
    // `step_key` em snake_case: é o nome do parâmetro no servidor, e o corpo vai como JSON cru.
    expect(requisicoes[0].body.step_key).toBe('phoneNumber');
  });

  it('leva o `website_token`: sem ele o `BaseController` procura o canal por `nil` e devolve 404', () => {
    // Asserção POSITIVA de propósito. «Não manda token errado» passaria também num módulo que
    // não manda requisição nenhuma, e o defeito deste bloco é justamente «nada chega».
    expect(requisicoes).not.toHaveLength(0);

    requisicoes.forEach(requisicao => {
      const naQuery = requisicao.params.website_token;
      const noCorpo = requisicao.body.website_token;
      expect(naQuery ?? noCorpo).toBe(SENTINELA_TOKEN);
    });
  });

  it('o token vem do canal, não é constante embutida no módulo', async () => {
    // Trocar o valor do canal e exigir que a rede acompanhe é o que separa «lê o canal» de
    // «tem um token escrito dentro» — a asserção acima sozinha só compara com o que o próprio
    // teste plantou.
    const outras = await capturar('OUTRO-TOKEN-DE-CANAL');

    expect(outras.map(r => r.body.website_token)).toEqual([
      'OUTRO-TOKEN-DE-CANAL',
    ]);
  });

  it('sem canal no documento não sai requisição condenada ao 404', async () => {
    // Par negativo do exemplo acima, e ele só vale por viver ao lado dele: sozinho, passaria
    // num módulo que nunca manda nada. Requisição condenada não é neutra — ela pinta o NOSSO
    // endpoint de vermelho na aba Network do site do cliente (motivo do 2.13).
    expect(await capturar(null)).toEqual([]);
  });

  it('é a fixture que o request spec envia ao Rails, campo a campo', () => {
    const gravada = JSON.parse(fs.readFileSync(CAMINHO_FIXTURE, 'utf8'));

    expect(gravada.sentinel_website_token).toBe(SENTINELA_TOKEN);
    expect(gravada.requests).toEqual(requisicoes);
  });
});
