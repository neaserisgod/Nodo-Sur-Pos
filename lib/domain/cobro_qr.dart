// Dónde sale el QR de Mercado Pago al cobrar (El dueño, 2026-10-13: "necesito que la app cree un QR y lo muestre en la
// pantalla. Nada de terminal… que se pueda configurar"). Se elige en cada equipo (un celular puede mostrar el QR y otro usar la
// Point), y arranca en "automático": en la terminal si la sucursal tiene una elegida, en la pantalla si no. Así nadie tiene que
// configurar nada para cobrar con QR.
//
// El QR de la pantalla es una orden de Mercado Pago igual a la de la Point (`mp_servicios.js` en el sitio): lo lee cualquier
// billetera o banco. Débito y crédito siguen necesitando la terminal: una tarjeta no se cobra con un QR.

enum DondeQr {
  /// En la terminal si hay una elegida; si no, en la pantalla.
  automatico('automatico'),

  /// Siempre en la pantalla.
  pantalla('pantalla'),

  /// En la terminal Point (sin terminal elegida no hay dónde: sale en la pantalla).
  terminal('terminal'),

  /// Pregunta en cada cobro (con terminal; sin terminal, va directo a la pantalla).
  preguntar('preguntar');

  const DondeQr(this.clave);
  final String clave;

  static DondeQr desdeClave(String? clave) => values.firstWhere((d) => d.clave == clave, orElse: () => DondeQr.automatico);

  String get nombre => switch (this) {
        DondeQr.automatico => 'Automático',
        DondeQr.pantalla => 'En la pantalla',
        DondeQr.terminal => 'En la terminal Point',
        DondeQr.preguntar => 'Preguntar cada vez',
      };

  String get descripcion => switch (this) {
        DondeQr.automatico => 'En la terminal si tu sucursal tiene una; si no, en la pantalla.',
        DondeQr.pantalla => 'El QR aparece en este equipo y el cliente lo escanea con su billetera o su banco.',
        DondeQr.terminal => 'El QR aparece en la Point.',
        DondeQr.preguntar => 'Al cobrar con QR elegís pantalla o terminal.',
      };
}

/// Si el QR de este cobro va en la pantalla. [hayTerminal]: la sucursal tiene una Point elegida. Null: hay que preguntar.
bool? qrEnPantalla(DondeQr preferencia, {required bool hayTerminal}) {
  if (!hayTerminal) return true; // sin terminal no hay otro lugar
  return switch (preferencia) {
    DondeQr.automatico => false,
    DondeQr.pantalla => true,
    DondeQr.terminal => false,
    DondeQr.preguntar => null,
  };
}

/// Si se ofrecen débito y crédito: necesitan la terminal. [hayTerminal] null (no se sabe: sin internet o sin cuenta) los deja,
/// como siempre: el aviso llega al cobrar.
bool ofrecerTarjeta({required bool? hayTerminal}) => hayTerminal != false;
