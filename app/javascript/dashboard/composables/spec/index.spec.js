import { emitter } from 'shared/helpers/mitt';
import analyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { useTrack, useAlert } from '../index';

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    emit: vi.fn(),
  },
}));

// `importOriginal()` devolve o NAMESPACE do modulo ESM, que e somente-leitura:
// escrever `actual.default` lanca e mata a suite no carregamento — o arquivo some
// da contagem como "(0 test)". Devolver um objeto novo resolve.
vi.mock('dashboard/helper/AnalyticsHelper/index', async importOriginal => {
  const actual = await importOriginal();
  return { ...actual, default: { track: vi.fn() } };
});

describe('useTrack', () => {
  it('should call analyticsHelper.track and return a function', () => {
    const eventArgs = ['event-name', { some: 'data' }];
    useTrack(...eventArgs);
    expect(analyticsHelper.track).toHaveBeenCalledWith(...eventArgs);
  });
});

describe('useAlert', () => {
  it('should emit a newToastMessage event with the provided message and action', () => {
    const message = 'Toast message';
    const action = {
      type: 'link',
      to: '/app/accounts/1/conversations/1',
      message: 'Navigate',
    };
    useAlert(message, action);
    expect(emitter.emit).toHaveBeenCalledWith('newToastMessage', {
      message,
      action,
    });
  });

  it('should emit a newToastMessage event with the provided message and no action if action is null', () => {
    const message = 'Toast message';
    useAlert(message);
    expect(emitter.emit).toHaveBeenCalledWith('newToastMessage', {
      message,
      action: null,
    });
  });
});
