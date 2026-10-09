import { mount } from '@vue/test-utils';
import AudioPlayer from '../AudioPlayer.vue';

const mountPlayer = props =>
  mount(AudioPlayer, { props: { src: '/a.webm', ...props } });

describe('AudioPlayer do chat interno', () => {
  beforeEach(() => localStorage.clear());

  it('troca a velocidade 1× → 1,5× → 2× → 1× e lembra a escolha', async () => {
    const wrapper = mountPlayer();
    const speed = () => wrapper.findAll('button').at(-1);
    expect(speed().text()).toBe('1×');
    await speed().trigger('click');
    expect(speed().text()).toBe('1,5×');
    expect(localStorage.getItem('internal_chat_audio_rate')).toBe('1.5');
    await speed().trigger('click');
    expect(speed().text()).toBe('2×');
    await speed().trigger('click');
    expect(speed().text()).toBe('1×');
    localStorage.setItem('internal_chat_audio_rate', '2');
    expect(mountPlayer().findAll('button').at(-1).text()).toBe('2×');
  });

  it('áudio recebido mostra "não ouvido" até tocar', async () => {
    const wrapper = mountPlayer({ heardKey: 42 });
    expect(wrapper.find('[role="img"]').exists()).toBe(true);
    await wrapper.find('audio').trigger('playing');
    expect(wrapper.find('[role="img"]').exists()).toBe(false);
    expect(mountPlayer({ heardKey: 42 }).find('[role="img"]').exists()).toBe(
      false
    );
  });

  it('meu áudio (sem heardKey) não tem o ponto', () => {
    expect(mountPlayer().find('[role="img"]').exists()).toBe(false);
  });
});
