# Ventana propia — POS La Plazoleta

Mockups (formato .dc.html, usar como referencia visual, no es HTML plano):
- Main.dc.html   ventana con la pantalla Vender y la barra propia
- Barra.dc.html  estados de la barra (normal, sin foco, hover, maximizada, aviso)
- Cierre.dc.html diálogo al cerrar con la caja abierta

Paquete: window_manager. Barra de 40 px, fondo #f0f4f9, borde 1 px #c4c7c5. Botones 46 x 40 px, íconos 10 px, trazo 1 px #444746.
- Sacar la barra nativa: WindowOptions(titleBarStyle: TitleBarStyle.hidden, windowButtonVisibility: false) con windowManager.waitUntilReadyToShow.
- La barra va envuelta en DragToMoveArea (arrastra la ventana; doble clic maximiza/restaura).
- Botones: minimize(), maximize()/unmaximize() (ícono "restaurar" según isMaximized, escuchar con WindowListener), close().
- Hover: minimizar y maximizar #dde3ea; cerrar #c42b1c con ícono blanco. Sin foco: texto #747775, íconos #9aa0a6, marca #a8c7fa.
- Izquierda: marca 20 px azul #0b57d0 + "La Plazoleta" (Figtree 14/600). Chips: "Caja abierta" (#e6f4ea / #0d652d), "Respaldo hoy HH:mm" (12/500 #5e5e5e). Aviso si la caja de ayer quedó sin cerrar: #fef1e0 / #7a3a04.
- Cerrar con la caja abierta: setPreventClose(true) y en onWindowClose mostrar el diálogo: Ir a cerrar la caja (azul) / Seguir trabajando (tonal) / Cerrar igual (texto rojo #b3261e).
Tipografía Figtree, fondo #f0f4f9, azul #0b57d0.
