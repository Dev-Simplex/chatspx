import { shallowMount } from '@vue/test-utils';
import { computed } from 'vue';
import Message from '../Message.vue';
import TextBubble from '../bubbles/Text/Index.vue';
import BaseBubble from '../bubbles/Base.vue';
import MessageMeta from '../MessageMeta.vue';
import en from 'dashboard/i18n/locale/en/conversation.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/conversation.json';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {} }) }));
vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
  useAlert: vi.fn(),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ getters: {}, dispatch: vi.fn() }),
  useMapGetter: name =>
    computed(() => (name === 'inboxes/getInbox' ? () => ({}) : [])),
}));
vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () =>
    Object.fromEntries(
      [
        'isAFacebookInbox',
        'isALineChannel',
        'isAPIInbox',
        'isASmsInbox',
        'isATelegramChannel',
        'isATwilioChannel',
        'isAWebWidgetInbox',
        'isAWhatsAppChannel',
        'isAnEmailChannel',
        'isAnInstagramChannel',
        'isATiktokChannel',
      ].map(key => [key, computed(() => key === 'isAPIInbox')])
    ),
}));

vi.mock('dashboard/composables/useTranslations', () => ({
  useTranslations: () => ({ hasTranslations: computed(() => false) }),
}));

const raw = '*📱 Enviado do WhatsApp*\n\n💬 **Mensagem:**\n"Olá!"';
const mountMessage = (contentAttributes = {}, groupWithNext = false) =>
  shallowMount(Message, {
    props: {
      sender: { id: 38, type: 'user', name: 'Simplex', thumbnail: 'dono.png' },
      id: 1,
      messageType: 1,
      status: 'sent',
      private: true,
      content: raw,
      contentAttributes,
      groupWithNext,
      conversationId: 1,
      createdAt: 1750000000,
      currentUserId: 1,
    },
    global: {
      mocks: { $t: key => key },
      stubs: { TextBubble: false, BaseBubble: false, MessageMeta: false },
    },
  });

describe('phone reply display', () => {
  it('renders an outgoing bubble with clean content and one accessible phone indicator', () => {
    const wrapper = mountMessage(
      { whatsappPhoneReply: true, whatsappPhoneReplyContent: 'Olá!' },
      true
    );
    expect(wrapper.findComponent(TextBubble).exists()).toBe(true);
    expect(wrapper.findComponent(BaseBubble).classes()).toContain(
      'bg-n-solid-blue'
    );
    expect(wrapper.findComponent(BaseBubble).classes()).not.toContain(
      'bg-n-solid-amber'
    );
    expect(wrapper.findComponent(BaseBubble).classes()).toContain(
      'right-bubble'
    );
    expect(wrapper.find('formatted-content-stub').attributes('content')).toBe(
      'Olá!'
    );
    expect(
      wrapper
        .findComponent(MessageMeta)
        .find('[icon="i-lucide-lock-keyhole"]')
        .exists()
    ).toBe(false);
    const indicator = wrapper.findAll('[icon="i-lucide-smartphone"]');
    expect(indicator).toHaveLength(1);
    expect(indicator[0].attributes('title')).toBeTruthy();
    expect(indicator[0].attributes('aria-label')).toBe(
      indicator[0].attributes('title')
    );
  });

  it('keeps notes private and does not detect the marker in the frontend', () => {
    const wrapper = mountMessage();
    expect(wrapper.findComponent(BaseBubble).classes()).toContain(
      'bg-n-solid-amber'
    );
    expect(wrapper.find('formatted-content-stub').attributes('content')).toBe(
      raw
    );
    expect(
      wrapper
        .findComponent(MessageMeta)
        .find('[icon="i-lucide-lock-keyhole"]')
        .exists()
    ).toBe(true);
    expect(wrapper.find('[icon="i-lucide-smartphone"]').exists()).toBe(false);
  });

  it('shows the WhatsApp icon instead of the inbox photo or the token owner', () => {
    const wrapper = mountMessage({
      whatsappPhoneReply: true,
      whatsappPhoneReplyContent: 'Olá!',
      externalEcho: true,
    });
    const avatar = wrapper.find('avatar-stub');
    expect(avatar.attributes('iconname')).toBe('i-ri-whatsapp-fill');
    expect(avatar.attributes('name')).toBe('');
    expect(avatar.attributes('src')).toBe('');
  });

  it('translates the phone indicator in English and Brazilian Portuguese', () => {
    expect(en.CONVERSATION.WHATSAPP_PHONE_REPLY).toBe(
      'Sent directly from WhatsApp on the phone (agent not identified)'
    );
    expect(ptBR.CONVERSATION.WHATSAPP_PHONE_REPLY).toBe(
      'Enviada direto pelo WhatsApp do celular (sem identificar o atendente)'
    );
  });
});
