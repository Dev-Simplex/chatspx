import { mount } from '@vue/test-utils';
import { ref, computed } from 'vue';

import BaseBubble from '../bubbles/Base.vue';
import GroupAuthorAvatar from '../GroupAuthorAvatar.vue';
import { provideMessageContext } from '../provider.js';
import { buildGroupAuthor } from '../groupAuthorPresenter';
import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ getters: {}, dispatch: vi.fn() }),
  useMapGetter: () => computed(() => []),
}));

const LABELS = {
  unknownLabel: 'Participante não identificado',
  unknownHint: 'O WhatsApp não informou quem enviou esta mensagem.',
  sentBy: 'Enviado por',
};

const ROGERIO = {
  name: 'Rogerio José Da Silva',
  lid: '229480102662169',
  phone: '5566999991234',
};

// Base.vue lê tudo do contexto que o Message.vue provê; o host reproduz esse contrato
// sem arrastar o Message.vue inteiro (store, router, menu de contexto) para o teste.
const mountBubble = ({
  groupAuthor = null,
  groupWithPrevious = false,
} = {}) => {
  const Host = {
    components: { BaseBubble },
    setup() {
      provideMessageContext({
        variant: ref(MESSAGE_VARIANTS.USER),
        orientation: ref(ORIENTATION.LEFT),
        inReplyTo: ref(null),
        shouldGroupWithNext: ref(false),
        groupAuthor: ref(groupAuthor),
        groupWithPrevious: ref(groupWithPrevious),
        // Consumidos por MessageMeta
        status: ref('sent'),
        isPrivate: ref(false),
        createdAt: ref(1750000000),
        sourceId: ref(''),
        messageType: ref(0),
        contentAttributes: ref({}),
        starred: ref(false),
        conversationId: ref(null),
      });
      return {};
    },
    template: '<BaseBubble><span class="body" /></BaseBubble>',
  };

  return mount(Host, {
    global: { stubs: { MessageMeta: true } },
  });
};

describe('group author on the bubble', () => {
  it('renders the author name on the first message of the block', () => {
    const wrapper = mountBubble({
      groupAuthor: buildGroupAuthor(ROGERIO, LABELS),
    });

    expect(wrapper.text()).toContain('Rogerio José Da Silva');
  });

  it('paints the name with the deterministic colour in both themes', () => {
    const author = buildGroupAuthor(ROGERIO, LABELS);
    const wrapper = mountBubble({ groupAuthor: author });
    const style = wrapper.find('span[style]').attributes('style');

    expect(style).toContain(`--group-author-color: ${author.color}`);
    expect(style).toContain(`--group-author-color-dark: ${author.colorDark}`);
  });

  it('hides the author on the following messages of the same block', () => {
    const wrapper = mountBubble({
      groupAuthor: buildGroupAuthor(ROGERIO, LABELS),
      groupWithPrevious: true,
    });

    expect(wrapper.text()).not.toContain('Rogerio José Da Silva');
  });

  it('renders nothing new in a 1:1 conversation', () => {
    const oneToOne = mountBubble({ groupAuthor: null });
    const group = mountBubble({
      groupAuthor: buildGroupAuthor(ROGERIO, LABELS),
    });

    expect(oneToOne.html()).not.toContain('--group-author-color');
    expect(group.html()).toContain('--group-author-color');
  });

  it('never renders the technical identifier', () => {
    const wrapper = mountBubble({
      groupAuthor: buildGroupAuthor(ROGERIO, LABELS),
    });

    expect(wrapper.html()).not.toContain(ROGERIO.lid);
    expect(wrapper.html()).not.toContain('@lid');
  });

  it('shows the unidentified participant in neutral, italic type', () => {
    const wrapper = mountBubble({
      groupAuthor: buildGroupAuthor(
        { name: null, lid: '229480102662169', phone: null },
        LABELS
      ),
    });
    const name = wrapper.find('span[style]');

    expect(name.text()).toBe('Participante não identificado');
    expect(name.classes()).toContain('italic');
    expect(name.attributes('style')).toContain('--group-author-color: #667781');
  });
});

describe('GroupAuthorAvatar', () => {
  it('renders the helper initials and keeps the identifier out of the DOM', () => {
    const author = buildGroupAuthor(ROGERIO, LABELS);
    const wrapper = mount(GroupAuthorAvatar, { props: { author } });

    expect(wrapper.text()).toBe('RS');
    expect(wrapper.attributes('aria-label')).toBe(
      'Enviado por Rogerio José Da Silva'
    );
    expect(wrapper.html()).not.toContain(ROGERIO.lid);
  });

  it('renders a grey "?" for an unidentified participant', () => {
    const author = buildGroupAuthor(
      { name: null, lid: '1', phone: null },
      LABELS
    );
    const wrapper = mount(GroupAuthorAvatar, { props: { author } });

    expect(wrapper.text()).toBe('?');
    expect(wrapper.attributes('style')).toContain(
      '--group-author-color: #667781'
    );
  });
});
