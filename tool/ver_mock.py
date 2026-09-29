"""Muestra un mock .dc.html como árbol legible: etiquetas, textos y lo
esencial del estilo (fondo, tamaño de letra, grid/flex), sin SVG ni el menú.
Uso: python ver_mock.py Archivo.dc.html [--estilos]"""
import re, sys, html
from html.parser import HTMLParser

ruta = sys.argv[1]
estilos = '--estilos' in sys.argv
texto = open(ruta, encoding='utf-8').read()
cuerpo = texto.split('<x-dc>', 1)[1].split('</x-dc>', 1)[0]
cuerpo = re.sub(r'<helmet>.*?</helmet>', '', cuerpo, flags=re.S)
cuerpo = re.sub(r'<svg.*?</svg>', '[ico]', cuerpo, flags=re.S)
# el menú de secciones se repite en todos: afuera
cuerpo = re.sub(r'<sc-if value="\{\{menuOpen\}\}".*?</sc-if>', '', cuerpo, flags=re.S)

VACIAS = {'input', 'br', 'img', 'hr', 'meta', 'link', 'dc-import'}

def resumen_estilo(s):
    claves = []
    for k in ['display', 'grid-template-columns', 'flex-grow', 'width', 'height', 'background', 'font-size', 'font-weight', 'border-radius', 'gap', 'padding']:
        m = re.search(r'(?:^|;)\s*' + re.escape(k) + r'\s*:\s*([^;]+)', s)
        if m:
            claves.append(f'{k}:{m.group(1).strip()}')
    return ' '.join(claves)

class P(HTMLParser):
    def __init__(self):
        super().__init__()
        self.nivel = 0
        self.out = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        extra = []
        for k in ('list', 'as', 'value', 'onclick', 'aria-label', 'placeholder', 'type', 'name', 'role'):
            if k in a and a[k]:
                extra.append(f'{k}={a[k]}')
        if estilos and a.get('style'):
            e = resumen_estilo(a['style'])
            if e:
                extra.append('{' + e + '}')
        self.out.append('  ' * self.nivel + f'<{tag}' + (' ' + ' '.join(extra) if extra else '') + '>')
        if tag not in VACIAS:
            self.nivel += 1
    def handle_endtag(self, tag):
        if tag not in VACIAS:
            self.nivel = max(0, self.nivel - 1)
    def handle_data(self, data):
        t = ' '.join(data.split())
        if t:
            self.out.append('  ' * self.nivel + '"' + html.unescape(t) + '"')

p = P()
p.feed(cuerpo)
# colapsar líneas de un solo hijo texto
lineas = p.out
print('\n'.join(lineas))
