import { mount, flushPromises } from '@vue/test-utils';
import i18nMessages from 'dashboard/i18n';
import Audio from '../Audio.vue';

vi.mock('@vueuse/core', () => ({ useIntersectionObserver: vi.fn() }));
vi.mock('next/icon/Icon.vue', () => ({ default: { template: '<span />' } }));

const peaks = Array.from({ length: 64 }, (_, index) => index / 63);
const attachment = waveformPeaks => ({
  dataUrl: 'https://example.com/audio.mp3',
  ...(waveformPeaks === undefined ? {} : { waveformPeaks }),
});

const mountAudio = waveformPeaks =>
  mount(Audio, { props: { attachment: attachment(waveformPeaks) } });

const setDuration = async (wrapper, value = 100) => {
  const audio = wrapper.find('audio').element;
  Object.defineProperty(audio, 'duration', { configurable: true, value });
  await wrapper.find('audio').trigger('loadedmetadata');
  return audio;
};

describe('Audio waveform player', () => {
  it('renders 64 peaks and keeps the keyboard slider visually hidden', () => {
    expect(
      i18nMessages.en.CONVERSATION_SIDEBAR.MEDIA_SECTIONS.AUDIO_PROGRESS
    ).toBe('Audio progress');
    const wrapper = mountAudio(peaks);
    expect(wrapper.findAll('[data-testid="waveform-bar"]')).toHaveLength(64);
    expect(wrapper.find('input[type="range"]').classes()).toContain('sr-only');
  });

  it('keeps the original range control without peaks', () => {
    const wrapper = mountAudio();
    expect(wrapper.findAll('[data-testid="waveform-bar"]')).toHaveLength(0);
    expect(wrapper.find('input[type="range"]').classes()).not.toContain(
      'sr-only'
    );
  });

  it('seeks to the proportional time when the waveform is clicked', async () => {
    const wrapper = mountAudio(peaks);
    const audio = await setDuration(wrapper);
    vi.spyOn(audio, 'load').mockImplementation(() => {});
    const waveform = wrapper.find('[data-testid="waveform"]');
    vi.spyOn(waveform.element, 'getBoundingClientRect').mockReturnValue({
      left: 10,
      width: 200,
    });
    waveform.element.dispatchEvent(
      new MouseEvent('pointerdown', { bubbles: true, clientX: 60 })
    );
    await flushPromises();
    expect(audio.currentTime).toBe(25);
  });

  it('highlights half the bars at half the duration', async () => {
    const wrapper = mountAudio(peaks);
    const audio = await setDuration(wrapper);
    audio.currentTime = 50;
    await wrapper.find('audio').trigger('timeupdate');
    const bars = wrapper.findAll('[data-testid="waveform-bar"]');
    expect(
      bars.filter(bar => bar.classes().includes('bg-n-slate-12'))
    ).toHaveLength(32);
    expect(
      bars.filter(bar => bar.classes().includes('bg-n-slate-12/40'))
    ).toHaveLength(32);
  });
});
