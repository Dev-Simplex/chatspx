import CaptadorAPI from '../../integrations/captador';
import ApiClient from '../../ApiClient';

describe('#CaptadorAPI', () => {
  it('creates correct instance', () => {
    expect(CaptadorAPI).toBeInstanceOf(ApiClient);
    expect(CaptadorAPI).toHaveProperty('getLead');
    expect(CaptadorAPI).toHaveProperty('moveStage');
  });

  describe('requests', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
      post: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
      vi.clearAllMocks();
    });

    it('#getLead asks the ChatSPX proxy for the conversation lead', () => {
      CaptadorAPI.getLead(12);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/integrations/captador/lead',
        { params: { conversation_id: 12 } }
      );
    });

    it('#moveStage posts the stage through the proxy', () => {
      CaptadorAPI.moveStage(12, 3);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/integrations/captador/mover',
        { conversation_id: 12, etapa_id: 3 }
      );
    });
  });
});
