"""Captura los apartados de Nodo Sur POS (la app YA abierta) y los guarda livianos en WebP.

Instalar una vez:   pip install pywinauto pillow
Usar:               python capturar_app.py                 (todo, con la app abierta y en Venta)
                    python capturar_app.py --hoja          (además una sola imagen con todo: la más barata para mostrarle a Claude)
                    python capturar_app.py --descubrir     (lista los botones y textos que ve el script, para ajustar PASOS)
                    python capturar_app.py --solo venta,historial --calidad 45 --ancho 1000

Es SOLO NAVEGACIÓN: hace clic en pestañas, en la campanita y en Configuración, y nada más. No escribe, no usa el teclado
(en Venta, Esc cancela la venta entera) y no toca cobrar, anular, gastos ni "Cerrar caja" salvo con --incluir-cierre, que
abre la ventana del cierre, la captura y la cierra con "Cancelar" (no confirma nada).
Aun así, correlo con la caja sin ventas armadas.
"""
import argparse
import ctypes
import sys
import time
from pathlib import Path

from PIL import Image
from pywinauto import Desktop
from pywinauto.findwindows import ElementNotFoundError

# Cada paso: nombre del archivo, textos a tocar EN ORDEN antes de capturar, y textos a tocar después (para dejar todo cerrado).
# Los textos son los nombres que ve el lector de accesibilidad: si alguno no coincide, el script lo avisa y sigue;
# `--descubrir` muestra los nombres reales para corregirlos acá.
PASOS = [
    {"nombre": "01-venta", "clics": ["Venta"]},
    {"nombre": "02-venta-campanita", "clics": ["Notificaciones"], "despues": ["Notificaciones"]},
    {"nombre": "03-inicio", "clics": ["Inicio"]},
    {"nombre": "04-proveedores", "clics": ["Proveedores"]},
    {"nombre": "05-separaciones", "clics": ["Separaciones"]},
    {"nombre": "06-historial", "clics": ["Historial"]},
    {"nombre": "07-encargues", "clics": ["Encargues"]},
    {"nombre": "08-config-negocio", "clics": ["Configuración", "Negocio"]},
    {"nombre": "09-config-caja-y-cobros", "clics": ["Caja y cobros"]},
    {"nombre": "10-config-productos", "clics": ["Productos"]},
    {"nombre": "11-config-equipos-y-cuenta", "clics": ["Equipos y cuenta"]},
    {"nombre": "12-config-apariencia", "clics": ["Apariencia"], "despues": ["Venta"]},
    # Solo con --incluir-cierre: abre el cierre, lo captura y lo cierra con "Cancelar".
    {"nombre": "13-cierre", "clics": ["Venta", "Cerrar caja"], "despues": ["Cancelar"], "opcional": "cierre"},
]
ESPERA = 0.9  # segundos después de cada clic: las animaciones duran menos de 0,2 s; el resto es cargar datos


def ventana(patron):
    try:
        w = Desktop(backend="uia").window(title_re=patron)
        w.wait("exists", timeout=5)
        return w
    except Exception:
        sys.exit(f"No encontré una ventana con título que coincida con /{patron}/. Abrí la app o pasá --ventana 'parte del título'.")


def tocar(win, texto):
    try:
        win.child_window(title=texto, found_index=0).click_input()
        return True
    except (ElementNotFoundError, Exception):
        print(f"  ! no encontré '{texto}' (seguí con --descubrir para ver los nombres reales)")
        return False


def descubrir(win):
    vistos = set()
    for e in win.descendants():
        try:
            nombre = (e.window_text() or "").strip()
            tipo = e.element_info.control_type
        except Exception:
            continue
        if nombre and (tipo, nombre) not in vistos:
            vistos.add((tipo, nombre))
            print(f"{tipo:12} {nombre}")
    if not vistos:
        print("No se ve ningún elemento: la app todavía no expuso su árbol de accesibilidad. Probá de nuevo en unos segundos.")


def guardar(img, ruta, ancho, calidad):
    if ancho and img.width > ancho:
        img = img.resize((ancho, round(img.height * ancho / img.width)), Image.LANCZOS)
    img.convert("RGB").save(ruta, "WEBP", quality=calidad, method=6)
    return img


def hoja(imagenes, ruta, calidad, columnas=3, ancho_mini=520):
    minis = []
    for img in imagenes:
        h = round(img.height * ancho_mini / img.width)
        minis.append(img.resize((ancho_mini, h), Image.LANCZOS))
    filas = [minis[i:i + columnas] for i in range(0, len(minis), columnas)]
    alto = sum(max(m.height for m in f) for f in filas)
    lienzo = Image.new("RGB", (columnas * ancho_mini, alto), "white")
    y = 0
    for f in filas:
        for i, m in enumerate(f):
            lienzo.paste(m, (i * ancho_mini, y))
        y += max(m.height for m in f)
    lienzo.save(ruta, "WEBP", quality=calidad, method=6)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ventana", default=".*(Nodo Sur|Plazoleta).*", help="expresión regular del título de la ventana")
    ap.add_argument("--salida", default="capturas_app", help="carpeta de salida")
    ap.add_argument("--calidad", type=int, default=55, help="WebP 1-100 (menos = más liviano; por debajo de 40 el texto se ensucia)")
    ap.add_argument("--ancho", type=int, default=1280, help="ancho máximo en píxeles (0 = tamaño original)")
    ap.add_argument("--solo", default="", help="nombres de pasos separados por coma (parte del nombre alcanza)")
    ap.add_argument("--hoja", action="store_true", help="además arma hoja.webp con todas las capturas juntas")
    ap.add_argument("--incluir-cierre", action="store_true", help="abre el cierre de caja, lo captura y lo cancela")
    ap.add_argument("--descubrir", action="store_true", help="lista los nombres que ve el script y sale")
    a = ap.parse_args()

    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)  # coordenadas reales en pantallas con escala
    except Exception:
        pass

    win = ventana(a.ventana)
    win.set_focus()
    time.sleep(0.5)
    if a.descubrir:
        descubrir(win)
        return

    salida = Path(a.salida)
    salida.mkdir(parents=True, exist_ok=True)
    filtro = [s.strip() for s in a.solo.split(",") if s.strip()]
    hechas, total = [], 0
    for paso in PASOS:
        if paso.get("opcional") == "cierre" and not a.incluir_cierre:
            continue
        if filtro and not any(f in paso["nombre"] for f in filtro):
            continue
        print(paso["nombre"])
        for t in paso["clics"]:
            tocar(win, t)
            time.sleep(ESPERA)
        win.set_focus()
        img = win.capture_as_image()
        ruta = salida / f"{paso['nombre']}.webp"
        hechas.append(guardar(img, ruta, a.ancho, a.calidad))
        total += ruta.stat().st_size
        print(f"  {ruta.name}  {ruta.stat().st_size // 1024} KB")
        for t in paso.get("despues", []):
            tocar(win, t)
            time.sleep(ESPERA)

    if a.hoja and hechas:
        ruta = salida / "hoja.webp"
        hoja(hechas, ruta, a.calidad)
        print(f"hoja.webp  {ruta.stat().st_size // 1024} KB")
    print(f"\n{len(hechas)} capturas, {total // 1024} KB en total, en {salida.resolve()}")


if __name__ == "__main__":
    main()
