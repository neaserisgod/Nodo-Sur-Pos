// La comandera de Nodo Gastro en este equipo (`servicios/comandera_point.dart`): una por proceso, sobre la base del celular, e
// imprime por el servidor de Nodo Sur con el Mercado Pago del negocio, como el ticket sin la PC (`PuertoLocal.imprimirTicket`).

import '../servicios/impresion_posnet_nube.dart' show imprimirContenidoPosnet;
import '../servicios/comandera_point.dart';
import 'base_local.dart';
import 'sync_nube_companion.dart';

ComanderaPoint? _comandera;

/// La de la app real. Se arma la primera vez que se pide.
ComanderaPoint comanderaDelCelular() => _comandera ??= ComanderaPoint(
      db: baseLocalCompanion(),
      imprimir: (contenido, {required idempotencyKey, required externalReference}) async {
        final sync = await syncNubeDelCelular();
        await imprimirContenidoPosnet(
          contenido: contenido,
          idempotencyKey: idempotencyKey,
          externalReference: externalReference,
          forzarNube: true,
          almacen: sync.almacen,
          cliente: sync.cliente,
        );
      },
    );

/// Para cambiar de negocio o borrar el equipo (`frenarLoQueEscribe`): la del negocio que viene se arma de nuevo sobre su base.
void soltarComandera() {
  _comandera?.detener();
  _comandera = null;
}
