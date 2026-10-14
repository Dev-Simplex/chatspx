import { setColorTheme } from 'dashboard/helper/themeHelper.js';
import { LocalStorage } from 'shared/helpers/localStorage';

vi.mock('shared/helpers/localStorage');

describe('setColorTheme', () => {
  it('should set body class to dark if selectedColorScheme is dark', () => {
    LocalStorage.get.mockReturnValue('dark');
    setColorTheme(true);
    expect(document.body.classList.contains('dark')).toBe(true);
  });

  it('should set body class to dark if selectedColorScheme is auto and isOSOnDarkMode is true', () => {
    LocalStorage.get.mockReturnValue('auto');
    setColorTheme(true);
    expect(document.body.classList.contains('dark')).toBe(true);
  });

  it('should not set body class to dark if selectedColorScheme is auto and isOSOnDarkMode is false', () => {
    LocalStorage.get.mockReturnValue('auto');
    setColorTheme(false);
    expect(document.body.classList.contains('dark')).toBe(false);
  });

  it('should not set body class to dark if selectedColorScheme is light', () => {
    LocalStorage.get.mockReturnValue('light');
    setColorTheme(true);
    expect(document.body.classList.contains('dark')).toBe(false);
  });

  it('should not set body class to dark if selectedColorScheme is undefined', () => {
    LocalStorage.get.mockReturnValue(undefined);
    setColorTheme(true);
    expect(document.body.classList.contains('dark')).toBe(true);
  });

  it('should set documentElement style to dark if selectedColorScheme is dark', () => {
    LocalStorage.get.mockReturnValue('dark');
    setColorTheme(true);
    expect(document.documentElement.getAttribute('style')).toBe(
      'color-scheme: dark;'
    );
  });

  it('should set documentElement style to dark if selectedColorScheme is auto and isOSOnDarkMode is true', () => {
    LocalStorage.get.mockReturnValue('auto');
    setColorTheme(true);
    expect(document.documentElement.getAttribute('style')).toBe(
      'color-scheme: dark;'
    );
  });

  it('should set documentElement style to light if selectedColorScheme is auto and isOSOnDarkMode is false', () => {
    LocalStorage.get.mockReturnValue('auto');
    setColorTheme(false);
    expect(document.documentElement.getAttribute('style')).toBe(
      'color-scheme: light;'
    );
  });

  it('should set documentElement style to light if selectedColorScheme is light', () => {
    LocalStorage.get.mockReturnValue('light');
    setColorTheme(true);
    expect(document.documentElement.getAttribute('style')).toBe(
      'color-scheme: light;'
    );
  });

  it('should set documentElement style to light if selectedColorScheme is undefined', () => {
    LocalStorage.get.mockReturnValue(undefined);
    setColorTheme(true);
    expect(document.documentElement.getAttribute('style')).toBe(
      'color-scheme: dark;'
    );
  });

  it('applies the theme and swallows the rejection when the transition is skipped', async () => {
    const skipped = () =>
      Promise.reject(new DOMException('Transition was skipped', 'AbortError'));
    document.startViewTransition = vi.fn(update => {
      update();
      return { ready: skipped(), finished: skipped() };
    });
    LocalStorage.get.mockReturnValue('dark');
    const unhandled = vi.fn();
    process.on('unhandledRejection', unhandled);

    setColorTheme(false);
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });

    process.off('unhandledRejection', unhandled);
    delete document.startViewTransition;
    expect(document.body.classList.contains('dark')).toBe(true);
    expect(unhandled).not.toHaveBeenCalled();
  });
});
