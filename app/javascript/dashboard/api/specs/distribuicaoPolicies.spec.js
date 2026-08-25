import distribuicaoPolicies from '../distribuicaoPolicies';
import ApiClient from '../ApiClient';

describe('#DistribuicaoPoliciesAPI', () => {
  it('creates correct instance', () => {
    expect(distribuicaoPolicies).toBeInstanceOf(ApiClient);
    expect(distribuicaoPolicies).toHaveProperty('get');
    expect(distribuicaoPolicies).toHaveProperty('show');
    expect(distribuicaoPolicies).toHaveProperty('upsert');
    expect(distribuicaoPolicies).toHaveProperty('delete');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
      put: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      Object.defineProperty(distribuicaoPolicies, 'accountIdFromRoute', {
        get: () => '1',
        configurable: true,
      });
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#get lista políticas e times da conta', () => {
      distribuicaoPolicies.get();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/distribuicao_policies'
      );
    });

    it('#show é chaveado pelo id do TIME, não pelo id da política', () => {
      distribuicaoPolicies.show(7);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/distribuicao_policies/7'
      );
    });

    it('#upsert manda PUT com o corpo embrulhado em `policy`', () => {
      distribuicaoPolicies.upsert(7, { ativo: true, modo: 'rodizio' });
      expect(axiosMock.put).toHaveBeenCalledWith(
        '/api/v1/accounts/1/distribuicao_policies/7',
        { policy: { ativo: true, modo: 'rodizio' } }
      );
    });

    it('#delete desliga o motor do time', () => {
      distribuicaoPolicies.delete(7);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/accounts/1/distribuicao_policies/7'
      );
    });
  });
});
