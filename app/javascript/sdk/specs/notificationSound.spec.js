import { IFrameHelper } from '../IFrameHelper';

/**
 * Bloco 4.11: **som desligado por default, opcao por inbox**.
 *
 * Hoje o som toca sozinho: qualquer interacao do visitante faz o SDK baixar o
 * mp3, e toda mensagem de agente toca. A decisao de produto e o contrario, e a
 * politica mora no lado que TOCA — nao so no widget que pede.
 */
describe('o som é opt-in por inbox', () => {
  beforeEach(() => {
    IFrameHelper.notificationSoundEnabled = false;
    window.playAudioAlert = vi.fn();
    IFrameHelper.titleFlasher = {
      start: vi.fn(),
      stop: vi.fn(),
      attach: vi.fn(),
      detach: vi.fn(),
    };
  });

  it('lê a opção da configuração do canal', () => {
    expect(
      IFrameHelper.isNotificationSoundEnabled({
        enabledFeatures: ['attachments', 'notification_sound'],
      })
    ).toBe(true);
  });

  it('inbox sem a opção fica sem som — e é o caso de toda inbox de hoje', () => {
    expect(
      IFrameHelper.isNotificationSoundEnabled({
        enabledFeatures: ['attachments', 'emoji_picker'],
      })
    ).toBe(false);
    // e configuracao ausente ou malformada tambem nao liga nada
    expect(IFrameHelper.isNotificationSoundEnabled(undefined)).toBe(false);
    expect(IFrameHelper.isNotificationSoundEnabled({})).toBe(false);
    expect(
      IFrameHelper.isNotificationSoundEnabled({ enabledFeatures: 'todas' })
    ).toBe(false);
  });

  it('sem opt-in, o evento playAudio NÃO toca nada', () => {
    IFrameHelper.events.playAudio({ title: 'Nova mensagem' });

    expect(window.playAudioAlert).not.toHaveBeenCalled();
  });

  it('com opt-in, toca', () => {
    IFrameHelper.notificationSoundEnabled = true;

    IFrameHelper.events.playAudio({ title: 'Nova mensagem' });

    expect(window.playAudioAlert).toHaveBeenCalledTimes(1);
  });

  it('o piscar do título é INDEPENDENTE do som — acontece mesmo sem opt-in', () => {
    IFrameHelper.events.playAudio({ title: 'Nova mensagem' });

    expect(IFrameHelper.titleFlasher.start).toHaveBeenCalledWith(
      'Nova mensagem'
    );
    expect(window.playAudioAlert).not.toHaveBeenCalled();
  });

  it('voltar para a conversa para o piscar', () => {
    // `resetUnreadMode` tambem mexe na classe do holder; sem o elemento no DOM
    // o teste morreria antes de chegar no que interessa
    document.body.innerHTML = '<div class="woot-widget-holder"></div>';

    IFrameHelper.events.resetUnreadMode();

    expect(IFrameHelper.titleFlasher.stop).toHaveBeenCalledTimes(1);
  });
});
