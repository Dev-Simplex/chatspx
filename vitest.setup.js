import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import i18nMessages from 'dashboard/i18n';
import FloatingVue from 'floating-vue';
import { vi } from 'vitest';

// lottie-web initializes a canvas renderer as soon as it is imported. jsdom
// has no canvas context, so dashboard tests that reach the agents routes need
// the renderer stubbed even when they never mount a Lottie icon.
vi.mock('lottie-web', () => ({
  default: {
    loadAnimation: () => ({
      addEventListener: () => {},
      destroy: () => {},
      goToAndPlay: () => {},
      goToAndStop: () => {},
      play: () => {},
      setDirection: () => {},
      setSpeed: () => {},
      stop: () => {},
    }),
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: i18nMessages,
});

config.global.plugins = [i18n, FloatingVue];
config.global.stubs = {
  WootModal: { template: '<div><slot/></div>' },
  WootModalHeader: { template: '<div><slot/></div>' },
  NextButton: { template: '<button><slot/></button>' },
};
