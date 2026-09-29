// "¿Cómo vamos?" en cualquier momento del día, sin contar nada a mano
// (Bruno, 2026-09-07: "un botón de arqueo también para saber que tal
// vamos en cualquier momento sin tener que contar a mano las ventas del
// día") — efectivo/Mercado Pago esperados son las mismas fórmulas del
// cierre real (`cajaEsperadaCentavos`/`mpEsperadoCentavos`,
// `repositorio_cierre.dart`), y el resto es el mismo resumen por
// medio/proveedor que ya tiene un día histórico (Regla 3, `estadoCaja` en
// `servicio_companion.dart`). Nunca la diferencia de arqueo: esa necesita
// plata contada, justo lo que este botón evita — sigue siendo exclusiva
// del cierre real, en el escritorio (Regla 10).
//
// Contra [ServicioCompanion], no [ClienteCompanion] a secas (Bruno,
// 2026-09-18: "no debería tener que escanear ya, es innecesario") —
// funciona igual con o sin PC emparejada, misma fórmula corrida contra la
// base local sincronizada por Supabase cuando no hay PC (`PuertoLocal`).

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/tema/tokens.dart';
import 'cliente_companion.dart';
import 'mensaje_error.dart';
import 'pantalla_carga_historica.dart'
    show FilaDatoSimple, SeccionProductosSinDatos;
import 'servicio_companion.dart';
import 'tema/estado_error_companion.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';

class PantallaArqueo extends StatefulWidget {
  const PantallaArqueo({super.key, required this.servicio});

  final ServicioCompanion servicio;

  @override
  State<PantallaArqueo> createState() => _PantallaArqueoState();
}

class _PantallaArqueoState extends State<PantallaArqueo> {
  EstadoCajaCompanion? _estado;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final estado = await widget.servicio.estadoCaja();
      if (mounted) setState(() => _estado = estado);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arqueo'),
        actions: [
          IconButton(
            icon: const Icon(IconosPlazoleta.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? EstadoErrorCompanion(mensaje: _error!, onReintentar: _cargar)
            : _contenido(context),
      ),
    );
  }

  Widget _contenido(BuildContext context) {
    final estado = _estado;
    if (estado == null) return const SizedBox.shrink();
    final resumen = estado.resumen;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(Espaciado.lg),
        children: [
          Text(
            'Sin contar nada a mano — son los montos esperados según lo cargado hasta ahora.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.md),
          Superficie(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  formatearARS(resumen.totalCentavos),
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                Text(
                  '${estado.cantidadVentas} venta(s)',
                  style: TextStyle(color: context.colores.textoSecundario),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaciado.md),
          // Efectivo, Mercado Pago y la lata son tres cajas distintas
          // (mismo criterio que el cierre real del escritorio, que ya las
          // separa en bloques propios) — antes estaban apiladas en una
          // sola lista plana de seis líneas, sin nada que marcara dónde
          // termina una caja y empieza la otra.
          Superficie(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Efectivo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Espaciado.xs),
                FilaDatoSimple(
                  'Esperado',
                  formatearARS(estado.efectivoEsperadoCentavos),
                ),
                if (estado.redondeoAcumuladoCentavos > 0)
                  FilaDatoSimple(
                    'Redondeo acumulado (ya incluido arriba)',
                    formatearARS(estado.redondeoAcumuladoCentavos),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Espaciado.sm),
          Superficie(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mercado Pago',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Espaciado.xs),
                FilaDatoSimple(
                  'Esperado',
                  formatearARS(estado.mpEsperadoCentavos),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaciado.sm),
          Superficie(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Lata de cigarrillos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Espaciado.xs),
                FilaDatoSimple(
                  'Arrastrada de antes de hoy',
                  formatearARS(estado.lataInicialCentavos),
                ),
                if (resumen.cigarrillosListaCentavos > 0)
                  FilaDatoSimple(
                    'A separar hoy (lista)',
                    formatearARS(resumen.cigarrillosListaCentavos),
                  ),
              ],
            ),
          ),
          SeccionProductosSinDatos(productos: resumen.productosSinDatos),
          const SizedBox(height: Espaciado.lg),
          Text('Por proveedor', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Espaciado.sm),
          if (resumen.porProveedor.isEmpty)
            Text(
              'Nada con proveedor y costo cargado todavía.',
              style: TextStyle(color: context.colores.textoSecundario),
            )
          else
            for (final p in resumen.porProveedor)
              Padding(
                padding: const EdgeInsets.only(bottom: Espaciado.sm),
                child: Superficie(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        p.nombreProveedor,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: Espaciado.xs),
                      FilaDatoSimple(
                        'Vendido',
                        formatearARS(p.vendidoCentavos),
                      ),
                      FilaDatoSimple(
                        'Separar (costo real)',
                        formatearARS(p.costoRealCentavos),
                      ),
                      FilaDatoSimple(
                        'Ganancia',
                        formatearARS(p.gananciaCentavos),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
