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
    // A regressão que isso trava: como filha, a tela renderizava com a barra
    // "Agentes IA / Nenhum agente encontrado" comendo um terço da largura.
    const filhas = (paiDeAgents?.children || []).map(rota => rota.name);
    expect(filhas).not.toContain('agents_rodizio');
    expect(painel).toBeDefined();
  });

  it('mantém a URL e o nome que o resto do app já empurra', () => {
    // `agents_rodizio` é para onde o item do Sidebar aponta.
    expect(painel.path).toBe('/app/accounts/:accountId/agents/rodizio');
  });

  it('não fica atrás da flag do Captain — rodízio não é IA', () => {
    // Sob CAPTAIN_V2 a tela sumia em qualquer conta sem o Captain ligado.
    expect(painel.meta.featureFlag).toBeUndefined();
  });

  it('continua sendo só para administrador', () => {
    expect(painel.meta.permissions).toEqual(['administrator']);
  });

  // A política do rodízio é POR TIME e passou a morar na edição do time, junto do checkbox de
  // atribuição automática. A rota antiga não pode sumir: link salvo e favorito de gestor virariam
  // 404. Ela fica como redirect para a lista de times, que é de onde se escolhe qual configurar.
  describe('a tela global de política, que foi removida', () => {
    it('não aponta mais para um componente', () => {
      expect(politica).toBeDefined();
      expect(politica.component).toBeUndefined();
    });

    it('redireciona para a lista de times, preservando a conta', () => {
      const destino = politica.redirect({ params: { accountId: '7' } });

      expect(destino).toEqual({
        name: 'settings_teams_list',
        params: { accountId: '7' },
      });
    });
  });

  it('não arrasta junto as telas de IA, que seguem sob a flag do Captain', () => {
    const dashboard = byName(paiDeAgents.children, 'agents_dashboard');
    expect(dashboard.meta.featureFlag).toBe(FEATURE_FLAGS.CAPTAIN_V2);
  });
});
