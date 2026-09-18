import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import BaseActionCableConnector from '../BaseActionCableConnector';

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    connection: { isOpen: () => true },
    subscriptions: { create: () => ({}) },
    disconnect: () => {},
  }),
}));

describe('BaseActionCableConnector', () => {
  let connector;
  let scrollTo;

  beforeEach(() => {
    vi.stubGlobal('scrollY', 120);
    vi.stubGlobal('scrollX', 0);
    scrollTo = vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
    connector = new BaseActionCableConnector(
      {
        $store: {
          getters: { getCurrentAccountId: 3, getCurrentUserID: 1 },
        },
      },
      'token'
    );
  });

  afterEach(() => {
    connector.disconnect();
    delete window.reconnectService;
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('recoloca a janela do dashboard ao voltar para o primeiro plano', () => {
    window.reconnectService = { handleRouteSpecificFetch: vi.fn() };

    connector.handleReturnToForeground();

    expect(scrollTo).toHaveBeenCalledWith(0, 0);
  });

  it('não altera a rolagem do widget ao voltar para o primeiro plano', () => {
    connector.handleReturnToForeground();

    expect(scrollTo).not.toHaveBeenCalled();
  });

  it('recoloca a janela do dashboard quando há rolagem horizontal', () => {
    vi.stubGlobal('scrollY', 0);
    vi.stubGlobal('scrollX', 80);
    window.reconnectService = { handleRouteSpecificFetch: vi.fn() };

    connector.handleReturnToForeground();

    expect(scrollTo).toHaveBeenCalledWith(0, 0);
  });
});
