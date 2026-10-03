import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;

import 'companion/companion_app.dart';
import 'data/database.dart';
import 'data/notificador_cambios.dart';
import 'domain/actualizacion.dart';
import 'servicios/comparador_precios.dart';
import 'servicios/actualizaciones.dart';
import 'servicios/actualizador_nativo.dart';
import 'servicios/comparador_precios_todoatucasa.dart';
import 'servidor/servidor_companion.dart';
import 'ui/venta/pantalla_venta.dart';
import 'ui/navegacion/route_observer.dart';
import 'ui/tema/simulador_resolucion.dart';
import 'ui/tema/tema.dart';
import 'ui/venta/venta_en_curso.dart';
import 'ui/ventana/ventana_escritorio.dart';
import 'domain/marca.dart';
import 'data/repositorio_configuracion.dart';
import 'domain/modulos.dart';
import 'servicios/modulos_activos.dart';
import 'servicios/nube.dart';
import 'servicios/preferencia_cobro_nube.dart';
import 'servicios/marca_actual.dart';
import 'servicios/registro_errores.dart';
import 'servicios/migracion_carpeta_datos.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  // El dueño, 2026-09-18: "quedó la pantalla en negro" — la causa real esa vez
  // fue una migración de base de datos que tiraba una excepción sin
  // capturar (ver el comentario de la migración v32 en `database.dart`),
  // pero cualquier excepción sin capturar en el arranque tiene el mismo
  // efecto: la ventana nativa se crea igual (por eso no se veía como un
  // crash), pero Flutter nunca llega a dibujar nada adentro. `runZonedGuarded`
  // es la red de seguridad general — que quede un rastro en la consola en
  // vez de una pantalla negra muda, sea cual sea la próxima causa.
  runZonedGuarded(_main, (error, stack) {
    registrarError('Error sin capturar', error, stack);
  });
}

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();
  instalarRegistroDeErrores();
  // Android es la companion app (2026-09-07): mismo proyecto, entrada
  // totalmente distinta — sin base de datos propia, sin servidor, solo un
  // cliente HTTP hacia la PC (ver `companion/`). Se decide antes que
  // cualquier otra cosa: ni `window_manager` (plugin de escritorio) ni
  // `AppDatabase()` tienen sentido acá.
  if (Platform.isAndroid) {
    runApp(const CompanionApp());
    return;
  }

  // Antes de que algo lea preferencias o la cuenta vinculada: si el nombre del producto cambió entre
  // versiones, la carpeta de datos de Windows cambió con él y hay que traer lo de la vieja.
  if (Platform.isWindows) {
    try {
      await migrarCarpetaDatosVieja(nueva: await getApplicationSupportDirectory());
    } catch (_) {
      // Nunca frenar el arranque por esto: peor caso, hay que volver a vincular.
    }
  }

  await PreferenciaCobroNube.cargar(); // interruptor de prueba "cobrar por Nodo Sur": se lee una vez, después va en memoria

  // Ventana propia (mocks `ventana-la-plazoleta/`, 2026-09-29): saca la
  // barra de título nativa y deja que la app decida el cierre. También
  // arranca el plugin que el simulador de resolución de debug necesita.
  await configurarVentanaEscritorio();
  runApp(LaPlazoletaApp(db: AppDatabase(), conVentanaPropia: true));
}

class LaPlazoletaApp extends StatefulWidget {
  const LaPlazoletaApp({super.key, required this.db, this.conVentanaPropia = false});

  final AppDatabase db;

  /// Solo la app real (`main`) dibuja la barra propia: los tests de widget
  /// pumpean esto sin plugin de ventana.
  final bool conVentanaPropia;

  @override
  State<LaPlazoletaApp> createState() => _LaPlazoletaAppState();
}

class _LaPlazoletaAppState extends State<LaPlazoletaApp> {
  Timer? _tickHorario;
  HttpServer? _servidorCompanion;
  StreamSubscription<MarcaNegocio>? _marcaSub;
  StreamSubscription<ModulosNegocio>? _modulosSub;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // El tema automático depende del reloj, no de ningún stream de la base
    // — sin este timer, la app quedaría en el modo de la hora en que
    // arrancó hasta el próximo cambio en `configuracion` (Regla: revisión
    // visual fase 13). Un minuto alcanza de sobra para un corte que solo
    // importa dos veces por día (10 y 22).
    _tickHorario = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() {}),
    );
    // El nombre del comercio que se ve en la ventana, el menú y el ticket sigue a la configuración.
    _marcaSub = seguirMarca(widget.db);
    // Los módulos que el comercio tiene apagados se esconden de la app (pantallas, botones, atajos).
    _modulosSub = seguirModulos(widget.db);
    _iniciarServidorCompanion();
    _actualizarComparacionPrecios();
    _actualizarComparacionPreciosTodoATuCasa();
    _iniciarActualizaciones();
    _iniciarNube();
  }

  // Cuenta de Nodo Sur (copias en la nube, versiones de prueba): solo en la app real, en segundo plano, y una
  // falla nunca frena el arranque.
  void _iniciarNube() {
    if (!widget.conVentanaPropia) return;
    iniciarNube(widget.db).then<void>((_) {}, onError: (Object error) {
      registrarError('Nube: no se pudo iniciar', error);
    });
  }

  // Actualizaciones (2026-09-30): solo en la app real (la de los tests de
  // widget no tiene plugin ni red). Revisa en segundo plano y nunca
  // interrumpe: sin internet no muestra nada, y con una venta abierta tampoco
  // avisa (`domain/actualizacion.dart`).
  void _iniciarActualizaciones() {
    if (!widget.conVentanaPropia) return;
    servicioActualizaciones ??= ServicioActualizaciones(
      cliente: http.Client(),
      versionActual: () async {
        final v = await leerVersionApp();
        return versionParaFeed(v.nombre, v.build);
      },
      ventaAbierta: hayVentaEnCurso,
      abrirInstalador: abrirActualizadorNativo,
    )..iniciar();
  }

  // Comparador de precios — dos fuentes independientes (El dueño,
  // 2026-09-14), cada una dispara sola, nunca bloquea el arranque ni un
  // frame de la venta, silenciosa si falla (sin internet, el sitio caído,
  // lo que sea). Cada servicio decide solo si hace falta bajar algo nuevo
  // (nada si su propia última actualización tiene menos de 20hs) y guarda
  // sin pisar lo de la otra fuente (`precios_referencia_externa.fuente`).
  Future<void> _actualizarComparacionPrecios() async {
    try {
      // Sin el módulo no se descarga nada (ni se gasta datos) para algo que no se ve.
      if (!(await modulosNegocioActuales(widget.db)).estaActivo(Modulo.compararPrecios)) return;
      await actualizarComparacionPrecios(widget.db);
    } catch (error) {
      registrarError('Comparador de precios (SEPA): no se pudo actualizar', error);
    }
  }

  Future<void> _actualizarComparacionPreciosTodoATuCasa() async {
    try {
      // Sin el módulo no se descarga nada (ni se gasta datos) para algo que no se ve.
      if (!(await modulosNegocioActuales(widget.db)).estaActivo(Modulo.compararPrecios)) return;
      await actualizarComparacionPreciosTodoATuCasa(widget.db);
    } catch (error) {
      registrarError('Comparador de precios (Todo a tu Casa): no se pudo actualizar', error);
    }
  }

  // Companion app Android (spike 2026-09-07): arranca en segundo plano, sin
  // bloquear el arranque de la app (CLAUDE.md, "prioridad arranque vs.
  // operación" — esto no es parte de la venta, no puede demorarla ni un
  // frame). Si el puerto ya está ocupado (dos instancias de la app, u otro
  // programa usándolo) o falla por cualquier otro motivo, la app de
  // escritorio sigue andando igual — la companion queda inalcanzable, pero
  // eso nunca puede tirar abajo la caja.
  Future<void> _iniciarServidorCompanion() async {
    // Antes que el servidor: `/companion/eventos` y las pantallas escuchan
    // este aviso para la sync instantánea por wifi (2026-09-28).
    notificadorCambios ??= NotificadorCambios(widget.db);
    try {
      _servidorCompanion = await iniciarServidorCompanion(widget.db);
    } catch (error) {
      registrarError('Companion: no se pudo levantar el servidor local', error);
    }
  }

  @override
  void dispose() {
    _tickHorario?.cancel();
    _marcaSub?.cancel();
    _modulosSub?.cancel();
    _servidorCompanion?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reactivo a `configuracion.temaOscuro`/`temaAutomatico`: cambiar el
    // switch en Configuración aplica el modo sin reiniciar la app.
    return StreamBuilder<Configuracion>(
      stream: widget.db.select(widget.db.configuracionTabla).watchSingle(),
      builder: (context, snapshot) {
        final automatico = snapshot.data?.temaAutomatico ?? true;
        final oscuro = automatico
            ? oscuroPorHorarioDelLocal(DateTime.now())
            : (snapshot.data?.temaOscuro ?? true);
        return MaterialApp(
          onGenerateTitle: (_) => marcaActual.value.nombre,
          debugShowCheckedModeBanner: false,
          locale: const Locale('es', 'AR'),
          supportedLocales: const [Locale('es', 'AR'), Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: TemaPlazoleta.claro,
          darkTheme: TemaPlazoleta.oscuro,
          themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
          navigatorKey: _navigatorKey,
          navigatorObservers: [routeObserver],
          builder: (context, child) {
            final app = SimuladorResolucion(child: child!);
            if (!widget.conVentanaPropia) return app;
            return MarcoVentana(db: widget.db, navigatorKey: _navigatorKey, child: app);
          },
          // Venta es la raíz de la app (El dueño, 2026-10-03: "que se vuelva a la pantalla de venta, mas no inicio"):
          // arranca ahí y la tecla Inicio vuelve ahí. El tablero ("Inicio") es una sección más de la navbar. Venta
          // resuelve sola los tres estados posibles al arrancar (sin sesión, sesión de un día anterior sin cerrar,
          // sesión normal) sin bloquear el resto de la app.
          home: PantallaVenta(db: widget.db),
        );
      },
    );
  }
}
