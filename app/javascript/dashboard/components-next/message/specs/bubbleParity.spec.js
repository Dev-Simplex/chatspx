import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import MessageMeta from '../MessageMeta.vue';
import Activity from '../bubbles/Activity.vue';
import FileBubble from '../bubbles/File.vue';
import ImageBubble from '../bubbles/Image.vue';
import Audio from '../chips/Audio.vue';
import DateSeparator from 'shared/components/DateSeparator.vue';

let context;
vi.mock('../provider.js', () => ({ useMessageContext: () => context }));
vi.mock('dashboard/composables/useInbox', () => ({ useInbox: () => ({}) }));
vi.mock(
  'dashboard/components/widgets/conversation/components/GalleryView.vue',
  () => ({ default: { template: '<div />' } })
);
vi.mock('dashboard/composables/emitter', () => ({ useEmitter: vi.fn() }));
vi.mock('dashboard/composables/loadWithRetry', () => ({
  useLoadWithRetry: () => ({
    isLoaded: ref(true),
    hasError: ref(false),
    loadWithRetry: vi.fn(),
  }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));

const render = component =>
  mount(component, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        MessageMeta: component !== MessageMeta,
        GalleryView: true,
        GroupAuthorName: true,
      },
      directives: {
        tooltip: (el, binding) => {
          el.title = binding.value;
        },
        dompurifyHtml: () => {},
      },
    },
  });

beforeEach(() => {
  context = Object.fromEntries(
    Object.entries({
      createdAt: new Date('2020-09-15T15:04:00Z').getTime() / 1000,
      status: 'sent',
      isPrivate: false,
      messageType: 0,
      contentAttributes: {},
      variant: 'user',
      orientation: 'left',
      inReplyTo: null,
      shouldGroupWithNext: false,
      groupAuthor: null,
      groupWithPrevious: false,
      content: 'Atividade',
      contentType: 'text',
      attachments: [
        { dataUrl: 'https://example.com/manual.pdf', fileSize: 1258291 },
      ],
    }).map(([key, value]) => [key, ref(value)])
  );
});

it('shows only HH:mm even for messages from another year', () => {
  expect(render(MessageMeta).find('time').text()).toBe('15:04');
});
it('uses HH:mm for activity timestamps', () => {
  expect(render(Activity).attributes('title')).toBe('15:04');
});
it('keeps the date on the day separator', () => {
  const wrapper = mount(DateSeparator, {
    props: { date: new Date('2020-09-15T15:04:00Z') },
    global: { mocks: { $t: key => key } },
  });
  expect(wrapper.text()).toContain('2020');
  expect(wrapper.text()).not.toBe('15:04');
});
const documentPayload = name => ({
  account_id: 1,
  data_url: `https://example.com/${name}`,
  extension: name.split('.').pop(),
  file_size: 1258291,
  file_type: 'file',
  height: null,
  id: 10,
  message_id: 28,
  thumb_url: '',
  width: null,
});

it.each(['manual.pdf', 'planilha-com-nome-muito-longo.xlsx'])(
  'keeps the size separate from the truncated name for %s',
  name => {
    // Same API payload and deep conversion used by MessageList; no file_name.
    const message = useCamelCase(
      { attachments: [documentPayload(name)] },
      {
        deep: true,
        stopPaths: [
          'content_attributes.translations',
          'content_attributes.interactive_payload',
        ],
      }
    );
    expect(message.attachments[0].fileSize).toBe(1258291);
    context.attachments.value = message.attachments;
    const wrapper = render(FileBubble);
    expect(wrapper.text()).toContain(name);
    const size = wrapper.get('[data-testid="file-size"]');
    expect(size.text()).toBe('1,2 MB');
    expect(size.classes()).toContain('shrink-0');
    expect(size.element.closest('.truncate')).toBeNull();
  }
);
it.each(['manual.pdf', 'planilha.xlsx'])(
  'also accepts an unconverted API attachment for %s',
  name => {
    context.attachments.value = [documentPayload(name)];
    const wrapper = render(FileBubble);
    expect(wrapper.text()).toContain(name);
    expect(wrapper.get('[data-testid="file-size"]').text()).toBe('1,2 MB');
    expect(wrapper.get('a').attributes('href')).toBe(
      `https://example.com/${name}`
    );
  }
);
it('omits the size when the payload has no size', () => {
  delete context.attachments.value[0].fileSize;
  expect(render(FileBubble).find('[data-testid="file-size"]').exists()).toBe(
    false
  );
});
it.each(['static.webp', 'animated.webp'])(
  'renders marked sticker %s without a bubble background',
  name => {
    context.contentType.value = 'sticker';
    context.attachments.value[0].dataUrl = `https://example.com/${name}`;
    const wrapper = render(ImageBubble);
    const bubble = wrapper.find('[data-bubble-name="image"]');
    expect(bubble.classes()).toContain('!bg-transparent');
    expect(bubble.classes()).toContain('!shadow-none');
    expect(bubble.classes()).not.toContain('bg-n-slate-4');
    expect(bubble.classes()).not.toContain('left-bubble');
    expect(wrapper.find('img').attributes('src')).toBe(
      `https://example.com/${name}`
    );
  }
);
it('keeps ordinary webp images styled as images', () => {
  context.attachments.value[0].dataUrl = 'https://example.com/photo.webp';
  expect(
    render(ImageBubble).find('[data-bubble-name="image"]').classes()
  ).not.toContain('!bg-transparent');
});
it('retains 2x after ending and applies it to the next audio, including already mounted players', async () => {
  vi.spyOn(HTMLMediaElement.prototype, 'load').mockImplementation(() => {});
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => {});
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockResolvedValue();
  const makeAudio = () =>
    mount(Audio, {
      props: { attachment: { dataUrl: 'https://example.com/audio.ogg' } },
    });
  const first = makeAudio();
  const second = makeAudio();
  await first.findAll('button')[1].trigger('click');
  await first.findAll('button')[1].trigger('click');
  await first.find('audio').trigger('ended');
  expect(first.text()).toContain('2x');
  await second.findAll('button')[0].trigger('click');
  await flushPromises();
  expect(second.find('audio').element.playbackRate).toBe(2);
  const third = makeAudio();
  expect(third.text()).toContain('2x');
  first.unmount();
  second.unmount();
  third.unmount();
  vi.restoreAllMocks();
});
