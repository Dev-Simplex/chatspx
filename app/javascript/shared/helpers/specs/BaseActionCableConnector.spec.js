import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import BaseActionCableConnector from '../BaseActionCableConnector';

const { createConsumer } = vi.hoisted(() => ({
  createConsumer: vi.fn(() => ({
    subscriptions: { create: vi.fn(() => ({ updatePresence: vi.fn() })) },
    connection: { isOpen: vi.fn(() => true) },
    disconnect: vi.fn(),
  })),
}));

vi.mock('@rails/actioncable', () => ({ createConsumer }));

describe('BaseActionCableConnector vigia', () => {
  let connector;
  let fetchRoute;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-09-17T12:00:00Z'));
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      value: false,
    });
    fetchRoute = vi.fn();
    window.reconnectService = { handleRouteSpecificFetch: fetchRoute };
    connector = new BaseActionCableConnector(
      {
        $store: {
          getters: { getCurrentAccountId: 1, getCurrentUserID: 2 },
        },
      },
      'token'
    );
  });

  afterEach(() => {
    connector.disconnect();
    window.dispatchEvent(new Event('focus'));
    delete window.reconnectService;
    delete document.hidden;
    vi.useRealTimers();
  });

  it('refaz a rota com a aba visível mesmo depois de perder o foco', () => {
    window.dispatchEvent(new Event('blur'));

    vi.advanceTimersByTime(30000);

    expect(fetchRoute).toHaveBeenCalledTimes(1);
  });

  it('passa três minutos de silêncio ao vigia', () => {
    connector.lastEventReceivedAt = Date.now() - 165000;

    vi.advanceTimersByTime(15000);

    expect(fetchRoute).toHaveBeenCalledWith({ staleSeconds: 180 });
  });

  it('passa vinte minutos de silêncio ao voltar para a aba', () => {
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      value: true,
    });
    vi.advanceTimersByTime(1200000);

    window.dispatchEvent(new Event('focus'));

    expect(fetchRoute).toHaveBeenCalledWith({ staleSeconds: 1200 });
  });

  it('não refaz a rota enquanto a aba está escondida', () => {
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      value: true,
    });

    vi.advanceTimersByTime(30000);

    expect(fetchRoute).not.toHaveBeenCalled();
  });
});

describe('BaseActionCableConnector ao voltar para o primeiro plano', () => {
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
    // Só o espião deste bloco: restoreAllMocks zeraria o createConsumer do vi.hoisted acima.
    scrollTo.mockRestore();
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
