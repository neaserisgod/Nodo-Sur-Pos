#!/usr/bin/env python3
"""Saca del repositorio los datos personales del comercio de origen (nombre del dueño, proveedores reales,
cliente recurrente, correo), reemplazándolos por nombres genéricos.

    python3 tool/limpiar_datos_personales.py            # solo muestra qué cambiaría
    python3 tool/limpiar_datos_personales.py --aplicar  # lo aplica

Se corre antes de hacer público el repositorio. Es idempotente: una segunda pasada no cambia nada. Después hay
que correr `flutter test`: los tests usan los mismos nombres que el código, así que cambian juntos.

No toca: nombres internos del código (`IconosPlazoleta`, `la_plazoleta`), que el usuario nunca ve; archivos
generados (`*.g.dart`); ni `build/`, `.git/` ni `.dart_tool/`.
"""
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
CARPETAS = ['lib', 'test', 'tool', 'installer', 'windows', 'android']
EXTENSIONES = {'.dart', '.md', '.ps1', '.sh', '.iss', '.py', '.kts', '.yaml'}
SALTAR = {'limpiar_datos_personales.py'}

# Frases completas primero (más específicas antes que las sueltas).
FRASES = [
    ('Serra Cigarros', 'Distribuidora de Cigarrillos'),
    ('Francisco de Biedma 179 - Km 8, Bariloche', 'Calle Falsa 123, Ciudad'),
    ('Km 8 del corredor Bustillo, San Carlos de Bariloche', 'ubicación del comercio de origen'),
    ('Jam Rock', 'Cliente Frecuente'),
    ('Contacto: Maca', 'Contacto: (nombre)'),
    ('gtalovergamer@gmail.com', 'tu-cuenta@ejemplo.com'),
]
PALABRAS = [
    ('Serra', 'Distribuidora'),
    ('Mazzota', 'Fiambrería'),
    ('Wesley', 'Golosinas Oeste'),
]
# "Bruno": el dueño. En comentarios y documentos es "el dueño" ("El dueño" al empezar una oración); en el
# código (nombres de usuario de prueba, textos) es "Dueño".
BRUNO = re.compile(r'\bBruno\b')


def _es_comentario(linea: str) -> bool:
    return linea.lstrip().startswith(('//', '///', '*', '#', '<!--'))


def _bruno(linea: str, md: bool) -> str:
    if md or _es_comentario(linea) or '//' in linea:
        def reemplazo(m):
            antes = linea[: m.start()].rstrip()
            inicio = not antes or antes.endswith(('.', ':', '//', '///', '*', '#', '"', '(', '—', '-')) and not antes[-1:].isalnum()
            return 'El dueño' if inicio else 'el dueño'
        return BRUNO.sub(reemplazo, linea)
    return BRUNO.sub('Dueño', linea)


def limpiar(texto: str, md: bool) -> str:
    for a, b in FRASES:
        texto = texto.replace(a, b)
    for a, b in PALABRAS:
        texto = re.sub(rf'\b{a}\b', b, texto)
    return ''.join(_bruno(l, md) for l in texto.splitlines(keepends=True))


def archivos():
    for carpeta in CARPETAS:
        for p in (RAIZ / carpeta).rglob('*'):
            if p.is_file() and p.suffix in EXTENSIONES and not p.name.endswith('.g.dart') and p.name not in SALTAR:
                if any(parte in {'build', '.dart_tool', '.git'} for parte in p.parts):
                    continue
                yield p
    for p in RAIZ.glob('*.md'):
        yield p
    for p in (RAIZ / 'docs').rglob('*.md') if (RAIZ / 'docs').exists() else []:
        yield p


def main():
    aplicar = '--aplicar' in sys.argv
    cambiados = 0
    for p in sorted(set(archivos())):
        try:
            original = p.read_text(encoding='utf-8')
        except UnicodeDecodeError:
            continue
        nuevo = limpiar(original, p.suffix == '.md')
        if nuevo != original:
            cambiados += 1
            print(('cambia  ' if aplicar else 'cambiaría  ') + str(p.relative_to(RAIZ)))
            if aplicar:
                p.write_text(nuevo, encoding='utf-8')
    print(f'\n{cambiados} archivo(s) {"modificados" if aplicar else "se modificarían"}.')


if __name__ == '__main__':
    main()
