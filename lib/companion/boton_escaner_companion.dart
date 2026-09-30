// Botón central de la navbar (El dueño, 2026-09-17: "en lugar de que sea un
// carrito el botón del medio, que sea un escáner") — reemplaza al carrito
// que tenía antes esa posición (`boton_carrito_companion.dart`, sacado:
// "vender" pasó a ser un acceso más en Inicio, junto a Gasto/Ingreso
// rápido). Escanea, busca por código y abre directo a editar (si ya existe)
// o a dar de alta completo (si no) — mismo mecanismo que ya tenía "Precios
// y alta de producto" con su propio botón de escanear, ahora acá en vez de
// ahí (esa pantalla quedó como búsqueda por nombre nada más).

import 'package:flutter/material.dart';

import '../ui/tema/tokens.dart';
import 'cliente_companion.dart';
import 'escanear_codigo.dart';
import 'mensaje_error.dart';
import 'navbar_companion.dart';
import 'pantalla_formulario_producto.dart';
import 'servicio_companion.dart';
import 'tema/colores_companion.dart';
import 'tema/resplandor.dart';
import '../ui/tema/iconos.dart';

class BotonEscanerCompanion extends StatefulWidget {
  const BotonEscanerCompanion({
    super.key,
    required this.servicio,
    required this.usuarioId,
    required this.proveedores,
    required this.categorias,
  });

  final ServicioCompanion? servicio;
  final int? usuarioId;
  final List<ProveedorCompanion> proveedores;
  final List<CategoriaCompanion> categorias;

  static const double _diametro = NavbarCompanion.diametroBoton;

  @override
  State<BotonEscanerCompanion> createState() => _BotonEscanerCompanionState();
}

class _BotonEscanerCompanionState extends State<BotonEscanerCompanion> {
  bool _buscando = false;

  Future<void> _escanear() async {
    if (widget.servicio == null || widget.usuarioId == null || _buscando) return;
    final codigo = await escanearCodigo(context);
    if (codigo == null || !mounted) return;
    setState(() => _buscando = true);
    try {
      final producto = await widget.servicio!.porCodigoBarras(codigo);
      if (!mounted) return;
      await mostrarFormularioProducto(
        context,
        cliente: widget.servicio!,
        usuarioId: widget.usuarioId!,
        proveedores: widget.proveedores,
        categorias: widget.categorias,
        producto: producto,
        codigoInicial: producto == null ? codigo : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeDeError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentos;
    final deshabilitado = widget.servicio == null || widget.usuarioId == null;
    return Container(
      width: BotonEscanerCompanion._diametro,
      height: BotonEscanerCompanion._diametro,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: deshabilitado
            ? null
            : LinearGradient(
                colors: acentos.gradienteAcento,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: deshabilitado ? colores.borde : null,
        // Resplandor de color en vez de sombra gris — el botón "flota" con
        // luz propia, mismo espíritu que el degradé (El dueño, 2026-09-18: "una
        // app moderna, útil y monetizable"; 2026-09-19: "cyberpunk me vuela
        // la gorra" — el helper compartido, `resplandorNeon`, es este mismo
        // halo que antes vivía solo acá, ahora reusado en toda la app).
        boxShadow: deshabilitado ? null : resplandorNeon(colores.acento, alpha: 0.45, radio: 18),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: deshabilitado ? null : _escanear,
          child: Center(
            child: _buscando
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colores.acentoTexto,
                    ),
                  )
                : Icon(IconosPlazoleta.qrCodeScanner, color: colores.acentoTexto),
          ),
        ),
      ),
    );
  }
}
