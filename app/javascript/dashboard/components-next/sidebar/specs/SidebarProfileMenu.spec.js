import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { provideDropdownContext } from 'next/dropdown-menu/base/provider.js';
import SidebarProfileMenu from '../SidebarProfileMenu.vue';

const { logoutSpy, openSpy } = vi.hoisted(() => ({
  logoutSpy: vi.fn(),
  openSpy: vi.fn(),
}));

vi.mock('dashboard/api/auth', () => ({ default: { logout: logoutSpy } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => false }),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: text => text }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    const values = {
      getCurrentUser: { available_name: 'Ana', email: 'ana@x.com' },
      'globalConfig/get': {},
      'accounts/isFeatureEnabledonAccount': () => false,
    };
    return ref(values[getter]);
  },
}));

const DialogStub = {
  name: 'Dialog',
  props: ['title', 'confirmButtonLabel'],
  emits: ['confirm'],
  methods: { open: openSpy },
  template: `<button data-testid="logout-confirm" @click="$emit('confirm')">{{ confirmButtonLabel }}</button>`,
};

// Menu sempre aberto: o teste é sobre o item de logout, não sobre o dropdown.
const DropdownContainerStub = {
  setup() {
    provideDropdownContext({ isOpen: ref(true), toggle() {}, closeMenu() {} });
  },
  template: '<div><slot /></div>',
};

const mountMenu = () =>
  mount(SidebarProfileMenu, {
    global: {
      stubs: {
        Dialog: DialogStub,
        DropdownContainer: DropdownContainerStub,
        Avatar: true,
        LordIconIcon: true,
        SidebarProfileMenuStatus: true,
        CustomBrandPolicyWrapper: {
          props: ['showOnCustomBrandedInstance'],
          template: '<slot />',
        },
        TeleportWithDirection: { template: '<slot />' },
      },
    },
  });

const clickLogoutItem = async wrapper => {
  const item = wrapper
    .findAll('.n-dropdown-item button')
    .find(b => b.text().includes('SIDEBAR_ITEMS.LOGOUT'));
  await item.trigger('click');
};

describe('SidebarProfileMenu logout', () => {
  beforeEach(() => vi.clearAllMocks());

  it('opens the confirmation instead of logging out', async () => {
    const wrapper = mountMenu();
    await clickLogoutItem(wrapper);

    expect(openSpy).toHaveBeenCalled();
    expect(logoutSpy).not.toHaveBeenCalled();
  });

  it('logs out only after confirming', async () => {
    const wrapper = mountMenu();
    await clickLogoutItem(wrapper);
    await wrapper.find('[data-testid="logout-confirm"]').trigger('click');

    expect(logoutSpy).toHaveBeenCalledTimes(1);
  });
});
