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

  it('não refaz a rota enquanto a aba está escondida', () => {
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      value: true,
    });

    vi.advanceTimersByTime(30000);

    expect(fetchRoute).not.toHaveBeenCalled();
  });
});
