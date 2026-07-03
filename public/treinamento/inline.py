#!/usr/bin/env python3
# Gera index.html (self-contained) a partir de index.src.html, embutindo CSS, reveal.js e logos.
import base64, pathlib
d = pathlib.Path(__file__).parent
html = (d / 'index.src.html').read_text()
reset = (d / 'assets/reset.css').read_text()
reveal_css = (d / 'assets/reveal.css').read_text()
theme = (d / 'assets/spx-theme.css').read_text()
reveal_js = (d / 'assets/reveal.js').read_text().replace('</script', '<\\/script')


def datauri(p):
    return 'data:image/svg+xml;base64,' + base64.b64encode((d / p).read_bytes()).decode()


logo = datauri('assets/brand/logo.svg')
bubble = datauri('assets/brand/logo_thumbnail2.svg')

for f in ['reset.css', 'reveal.css', 'spx-theme.css']:
    html = html.replace('  <link rel="stylesheet" href="assets/%s?v=9">\n' % f, '')

base_css = "<style>\n/* reset */\n%s\n/* reveal */\n%s\n/* spx-theme */\n%s\n</style>\n  " % (reset, reveal_css, theme)
html = html.replace('  <style>', '  ' + base_css + '<style>', 1)
html = html.replace('<script src="assets/reveal.js?v=9"></script>', '<script>\n' + reveal_js + '\n</script>')
html = html.replace('assets/brand/logo.svg?v=9', logo).replace('assets/brand/logo_thumbnail2.svg?v=9', bubble)

(d / 'index.html').write_text(html)
print('index.html =', len((d / 'index.html').read_bytes()), 'bytes')
