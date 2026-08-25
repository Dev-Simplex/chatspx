import { routes } from '../agents.routes';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const byName = (lista, nome) => lista.find(rota => rota.name === nome);

const paiDeAgents = routes.find(
  rota => rota.path === '/app/accounts/:accountId/agents'
);

const painel = byName(routes, 'agents_rodizio');
const politica = byName(routes, 'agents_rodizio_politica');

describe('rotas do rodízio', () => {
  it('não moram dentro do AgentsPageView', () => {
    // A regressão que isso trava: como filhas, as duas telas renderizavam com a
    // barra "Agentes IA / Nenhum agente encontrado" comendo um terço da largura.
    const filhas = (paiDeAgents?.children || []).map(rota => rota.name);
    expect(filhas).not.toContain('agents_rodizio');
    expect(filhas).not.toContain('agents_rodizio_politica');
    expect(painel).toBeDefined();
    expect(politica).toBeDefined();
  });

  it('mantém as URLs e os nomes que o resto do app já empurra', () => {
    // `agents_rodizio` é para onde o item do Sidebar e o botão "Voltar" da política
    // apontam; `agents_rodizio_politica` é o destino do botão "Configurar rodízio".
    expect(painel.path).toBe('/app/accounts/:accountId/agents/rodizio');
    expect(politica.path).toBe(
      '/app/accounts/:accountId/agents/rodizio/politica'
    );
  });

  it('não ficam atrás da flag do Captain — rodízio não é IA', () => {
    // Sob CAPTAIN_V2 a tela sumia em qualquer conta sem o Captain ligado.
    expect(painel.meta.featureFlag).toBeUndefined();
    expect(politica.meta.featureFlag).toBeUndefined();
  });

  it('continuam sendo só para administrador', () => {
    expect(painel.meta.permissions).toEqual(['administrator']);
    expect(politica.meta.permissions).toEqual(['administrator']);
  });

  it('não arrastam junto as telas de IA, que seguem sob a flag do Captain', () => {
    const dashboard = byName(paiDeAgents.children, 'agents_dashboard');
    expect(dashboard.meta.featureFlag).toBe(FEATURE_FLAGS.CAPTAIN_V2);
  });
});
