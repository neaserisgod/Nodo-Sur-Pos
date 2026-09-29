-- Esquema Postgres para la migración de sync de Firestore a Supabase
-- ("La Plazoleta"). Se corre UNA VEZ a mano en el SQL Editor del proyecto de
-- Supabase, recién creado — no lo ejecuta la app.
--
-- Espejo de las 16 tablas sincronizables de `lib/data/repositorio_sincronizacion.dart`
-- (`tablasSincronizables`) más `configuracion_cobro` (credenciales de la
-- terminal Point, antes el documento fijo `negocios/la-plazoleta/configuracion/cobro`
-- en Firestore).
--
-- Decisiones de tipos (para que `lib/data/transporte_supabase.dart` pueda
-- escribir/leer la fila cruda tal cual sale de SQLite, sin reinterpretar
-- nada — mismo principio que ya usaba el código de Firestore):
--   * Fechas: en SQLite/drift viajan como enteros (epoch en segundos), nunca
--     como timestamp — acá van `bigint`, no `timestamptz`.
--   * Booleanos: `smallint` (0/1), NO `boolean` nativo — drift entrega estas
--     columnas como enteros crudos (`repositorio_sincronizacion.dart`: "enteros
--     para fechas y booleanos"), y Postgres no castea implícitamente un
--     entero JSON a `boolean` vía PostgREST (falla el insert/upsert) — mismo
--     principio de "sin traducción" que las fechas.
--   * Todo lo demás: `text` o `bigint`, sin `varchar(n)` (no hace falta en
--     Postgres).
--   * `global_id` es la identidad real entre dispositivos y la PRIMARY KEY
--     acá — el `id` autoincrement de SQLite es local a cada dispositivo y
--     nunca viaja.
--   * `rev`: cursor de pull, NO existe en SQLite ni la ve el dominio. Un
--     trigger la asigna sola en cada INSERT/UPDATE desde una secuencia
--     compartida entre las 16 tablas sincronizables — `transporte_supabase.dart`
--     la usa para pedir "todo lo nuevo desde X" y la descarta antes de
--     aplicar la fila (ver la sección de triggers, al final de este archivo).
--   * Las columnas que en SQLite son claves foráneas a OTRA tabla
--     sincronizada (`categoria_id`, `proveedor_id`, `usuario_id`, etc.) NO
--     son foreign keys acá: viajan como el entero local del dispositivo que
--     mandó la fila (nunca coincide entre dos bases independientes — bug
--     real encontrado 2026-09-18, ver `_referenciasCruzadas` en
--     `lib/data/repositorio_sincronizacion.dart`). Por eso cada una de esas
--     columnas tiene una compañera `<columna>_gid text` con el `global_id`
--     de la fila referenciada — lo único que permite traducir el id al
--     que corresponde en la base que recibe. Ponerles FK de Postgres a las
--     columnas `_id` originales rompería igual cualquier upsert que llegue
--     en un orden distinto al de inserción, así que ninguna de las dos
--     lleva FK real acá.
--   * Todas las columnas no-PK quedan `null`-ables: esto es un espejo de
--     sync, no la fuente de verdad de integridad (esa la tiene cada SQLite
--     local) — más tolerante ante upserts parciales.

-- ============================================================
-- 1. usuarios
-- ============================================================
create table if not exists usuarios (
  global_id text primary key,
  rev bigint not null default 0,
  nombre text,
  activo smallint default 1,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 2. categorias
-- ============================================================
create table if not exists categorias (
  global_id text primary key,
  rev bigint not null default 0,
  nombre text,
  markup_default_bp bigint default 0,
  activo smallint default 1,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 3. proveedores
-- ============================================================
create table if not exists proveedores (
  global_id text primary key,
  rev bigint not null default 0,
  codigo text,
  nombre text,
  dia_pedido text,
  dia_entrega text,
  colchon_reposicion_centavos bigint default 0,
  medio_pago text default 'Efectivo',
  corte_reposicion_fecha bigint,
  pendiente_base_centavos bigint default 0,
  separado_centavos bigint default 0,
  separado_mp_centavos bigint default 0,
  separado_del_dia_fecha bigint,
  separado_del_dia_centavos bigint default 0,
  separado_del_dia_mp_centavos bigint default 0,
  corte_antes_del_dia bigint,
  pendiente_base_antes_del_dia_centavos bigint default 0,
  separado_fecha bigint,
  ultimo_pago_fecha bigint,
  ganancia_revisada_fecha bigint,
  activo smallint default 1,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 4. clientes
-- ============================================================
create table if not exists clientes (
  global_id text primary key,
  rev bigint not null default 0,
  nombre text,
  telefono text,
  descuento_bp bigint,
  notas text,
  activo smallint default 1,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 5. productos
-- ============================================================
create table if not exists productos (
  global_id text primary key,
  rev bigint not null default 0,
  codigo_barras text,
  nombre text,
  categoria_id bigint,
  categoria_id_gid text,
  proveedor_id bigint,
  proveedor_id_gid text,
  es_varios smallint default 0,
  tipo_cigarrillo text default 'ninguno',
  es_pesable smallint default 0,
  precio_centavos bigint,
  costo_centavos bigint,
  precio_por_kilo_centavos bigint,
  costo_por_kilo_centavos bigint,
  stock bigint default 0,
  stock_gramos bigint,
  stock_minimo bigint default 0,
  stock_minimo_gramos bigint,
  activo smallint default 1,
  creado_en bigint,
  actualizado_en bigint,
  origen_dispositivo text,
  stock_base_sincronizacion bigint,
  stock_gramos_base_sincronizacion bigint,
  stock_base_sincronizacion_fecha bigint
);

-- ============================================================
-- 6. sesiones_de_caja
-- ============================================================
create table if not exists sesiones_de_caja (
  global_id text primary key,
  rev bigint not null default 0,
  fecha_apertura bigint,
  fecha_cierre bigint,
  usuario_abrio_id bigint,
  usuario_abrio_id_gid text,
  usuario_cerro_id bigint,
  usuario_cerro_id_gid text,
  fondo_inicial_centavos bigint,
  lata_inicial_centavos bigint default 0,
  saldo_mp_inicial_centavos bigint default 0,
  efectivo_contado_centavos bigint,
  efectivo_esperado_centavos bigint,
  diferencia_centavos bigint,
  lata_separado_centavos bigint,
  lata_pendiente_centavos bigint,
  lata_final_centavos bigint,
  lata_contado_centavos bigint,
  lata_diferencia_centavos bigint,
  excedente_mp_cigarrillos_generado_centavos bigint,
  saldo_mp_final_centavos bigint,
  mp_contado_centavos bigint,
  mp_esperado_centavos bigint,
  mp_diferencia_centavos bigint,
  nota text,
  estado text default 'ABIERTA',
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 7. ventas
-- ============================================================
create table if not exists ventas (
  global_id text primary key,
  rev bigint not null default 0,
  sesion_caja_id bigint,
  sesion_caja_id_gid text,
  cliente_id bigint,
  cliente_id_gid text,
  usuario_id bigint,
  usuario_id_gid text,
  fecha bigint,
  subtotal_centavos bigint,
  descuento_centavos bigint default 0,
  recargo_cigarrillos_centavos bigint default 0,
  redondeo_centavos bigint default 0,
  total_centavos bigint,
  es_fiado smallint default 0,
  editada_por_id bigint,
  editada_por_id_gid text,
  editada_en bigint,
  motivo_edicion text,
  anulada_por_id bigint,
  anulada_por_id_gid text,
  anulada_en bigint,
  motivo_anulacion text,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 8. lineas_de_venta
-- ============================================================
create table if not exists lineas_de_venta (
  global_id text primary key,
  rev bigint not null default 0,
  venta_id bigint,
  venta_id_gid text,
  producto_id bigint,
  producto_id_gid text,
  nombre_producto_foto text,
  proveedor_id_foto bigint,
  proveedor_id_foto_gid text,
  es_varios smallint default 0,
  tipo_cigarrillo text default 'ninguno',
  es_pesable smallint default 0,
  cantidad bigint,
  gramos bigint,
  precio_unitario_centavos bigint,
  costo_unitario_centavos bigint,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 9. pagos
-- ============================================================
create table if not exists pagos (
  global_id text primary key,
  rev bigint not null default 0,
  venta_id bigint,
  venta_id_gid text,
  medio_pago_id bigint,
  monto_centavos bigint,
  canal text,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 10. movimientos_de_stock (log append-only, sin actualizado_en)
-- ============================================================
create table if not exists movimientos_de_stock (
  global_id text primary key,
  rev bigint not null default 0,
  producto_id bigint,
  producto_id_gid text,
  venta_id bigint,
  venta_id_gid text,
  usuario_id bigint,
  usuario_id_gid text,
  tipo text,
  cantidad bigint,
  stock_anterior bigint,
  stock_posterior bigint,
  gramos bigint,
  gramos_anterior bigint,
  gramos_posterior bigint,
  motivo text,
  fecha bigint,
  origen_dispositivo text
);

-- ============================================================
-- 11. movimientos_de_caja (log append-only, sin actualizado_en)
-- ============================================================
create table if not exists movimientos_de_caja (
  global_id text primary key,
  rev bigint not null default 0,
  sesion_caja_id bigint,
  sesion_caja_id_gid text,
  caja_id bigint,
  venta_id bigint,
  venta_id_gid text,
  gasto_fijo_id bigint,
  proveedor_id bigint,
  proveedor_id_gid text,
  medio_pago_id bigint,
  usuario_id bigint,
  usuario_id_gid text,
  tipo text,
  monto_centavos bigint,
  nota text,
  fecha bigint,
  origen_dispositivo text,
  uso_excedente_cigarrillos smallint default 0
);

-- ============================================================
-- 12. arqueos_intermedios (log append-only, sin actualizado_en)
-- ============================================================
create table if not exists arqueos_intermedios (
  global_id text primary key,
  rev bigint not null default 0,
  sesion_caja_id bigint,
  sesion_caja_id_gid text,
  usuario_id bigint,
  usuario_id_gid text,
  fecha bigint,
  efectivo_contado_centavos bigint,
  efectivo_esperado_centavos bigint,
  diferencia_centavos bigint,
  mp_contado_centavos bigint,
  mp_esperado_centavos bigint,
  mp_diferencia_centavos bigint,
  lata_contado_centavos bigint,
  lata_esperado_centavos bigint,
  lata_diferencia_centavos bigint,
  origen_dispositivo text
);

-- ============================================================
-- 13. historial_de_precios (log append-only, sin actualizado_en)
-- ============================================================
create table if not exists historial_de_precios (
  global_id text primary key,
  rev bigint not null default 0,
  producto_id bigint,
  producto_id_gid text,
  precio_centavos bigint,
  costo_centavos bigint,
  precio_por_kilo_centavos bigint,
  costo_por_kilo_centavos bigint,
  fecha bigint,
  usuario_id bigint,
  usuario_id_gid text,
  origen_dispositivo text
);

-- ============================================================
-- 14. pendientes
-- ============================================================
create table if not exists pendientes (
  global_id text primary key,
  rev bigint not null default 0,
  tipo text,
  cliente_id bigint,
  cliente_id_gid text,
  nombre_libre text,
  monto_centavos bigint,
  descripcion text,
  estado text default 'PENDIENTE',
  venta_id bigint,
  venta_id_gid text,
  fecha_creacion bigint,
  fecha_resuelta bigint,
  usuario_id bigint,
  usuario_id_gid text,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 15. configuracion_negocio_tabla (fila única — recargo de cigarrillos,
-- paso de redondeo, producto de vuelto; migración v32→v33, Bruno
-- 2026-09-19: "que se puedan modificar las reglas del negocio... desde el
-- celular"). Separada de `configuracion_tabla` (que NUNCA sincroniza:
-- mezcla estas reglas con secretos y datos de UI del escritorio) — ver
-- `lib/data/tables/configuracion_negocio.dart`.
-- ============================================================
create table if not exists configuracion_negocio_tabla (
  global_id text primary key,
  rev bigint not null default 0,
  recargo_primer_atado_centavos bigint default 30000,
  recargo_atado_adicional_centavos bigint default 10000,
  recargo_suelto_centavos bigint default 5000,
  paso_redondeo_centavos bigint default 10000,
  producto_vuelto_id bigint,
  producto_vuelto_id_gid text,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 16. medios_de_pago (2 filas fijas — Efectivo/Mercado Pago, `global_id`
-- fijo y determinístico en el código, no aleatorio: ver
-- `_globalIdMedioPagoEfectivo`/`_globalIdMedioPagoVirtual` en
-- `lib/data/database.dart`, migración v32→v33)
-- ============================================================
create table if not exists medios_de_pago (
  global_id text primary key,
  rev bigint not null default 0,
  nombre text,
  es_efectivo smallint default 0,
  orden bigint default 0,
  activo smallint default 1,
  origen_dispositivo text,
  actualizado_en bigint
);

-- ============================================================
-- 17. configuracion_cobro (fila única, credenciales de la terminal Point)
-- ============================================================
create table if not exists configuracion_cobro (
  id bigint primary key default 1 check (id = 1),
  mp_access_token text,
  mp_terminal_cobro_id text
);

-- ============================================================
-- Cursor de pull: secuencia compartida entre las 16 tablas sincronizables +
-- trigger que le asigna un valor nuevo a `rev` en cada INSERT o UPDATE.
-- `configuracion_cobro` no participa (no tiene pull con cursor, solo
-- get/set puntual). Ver `lib/data/transporte_supabase.dart` para el porqué.
-- ============================================================
create sequence if not exists sync_rev_seq;

-- Un upsert que llega con exactamente los mismos datos que ya hay se
-- descarta (`return null` en un BEFORE UPDATE cancela esa fila, sin error):
-- no gasta un `rev`, no escribe, y no genera un mensaje de Realtime. Bug
-- real del 2026-09-26 — la app re-subía las mismas filas en bucle y cada
-- una pisaba `rev`, así que el otro dispositivo (y el mismo) las volvía a
-- bajar: 20,7 millones de `rev` para ~2.000 filas y la cuota del plan
-- gratis agotada. El arreglo de fondo está en la app
-- (`filtrarYaSubidas`, `lib/data/repositorio_sincronizacion.dart`); esto
-- es la red de seguridad para cualquier build viejo que siga instalado.
create or replace function sync_asignar_rev() returns trigger as $$
begin
  if tg_op = 'UPDATE' and (to_jsonb(new) - 'rev') = (to_jsonb(old) - 'rev') then
    return null;
  end if;
  new.rev := nextval('sync_rev_seq');
  return new;
end;
$$ language plpgsql;

create trigger trg_usuarios_rev before insert or update on usuarios
  for each row execute function sync_asignar_rev();
create index if not exists usuarios_rev_idx on usuarios (rev);

create trigger trg_categorias_rev before insert or update on categorias
  for each row execute function sync_asignar_rev();
create index if not exists categorias_rev_idx on categorias (rev);

create trigger trg_proveedores_rev before insert or update on proveedores
  for each row execute function sync_asignar_rev();
create index if not exists proveedores_rev_idx on proveedores (rev);

create trigger trg_clientes_rev before insert or update on clientes
  for each row execute function sync_asignar_rev();
create index if not exists clientes_rev_idx on clientes (rev);

create trigger trg_productos_rev before insert or update on productos
  for each row execute function sync_asignar_rev();
create index if not exists productos_rev_idx on productos (rev);

create trigger trg_sesiones_de_caja_rev before insert or update on sesiones_de_caja
  for each row execute function sync_asignar_rev();
create index if not exists sesiones_de_caja_rev_idx on sesiones_de_caja (rev);

create trigger trg_ventas_rev before insert or update on ventas
  for each row execute function sync_asignar_rev();
create index if not exists ventas_rev_idx on ventas (rev);

create trigger trg_lineas_de_venta_rev before insert or update on lineas_de_venta
  for each row execute function sync_asignar_rev();
create index if not exists lineas_de_venta_rev_idx on lineas_de_venta (rev);

create trigger trg_pagos_rev before insert or update on pagos
  for each row execute function sync_asignar_rev();
create index if not exists pagos_rev_idx on pagos (rev);

create trigger trg_movimientos_de_stock_rev before insert or update on movimientos_de_stock
  for each row execute function sync_asignar_rev();
create index if not exists movimientos_de_stock_rev_idx on movimientos_de_stock (rev);

create trigger trg_movimientos_de_caja_rev before insert or update on movimientos_de_caja
  for each row execute function sync_asignar_rev();
create index if not exists movimientos_de_caja_rev_idx on movimientos_de_caja (rev);

create trigger trg_arqueos_intermedios_rev before insert or update on arqueos_intermedios
  for each row execute function sync_asignar_rev();
create index if not exists arqueos_intermedios_rev_idx on arqueos_intermedios (rev);

create trigger trg_historial_de_precios_rev before insert or update on historial_de_precios
  for each row execute function sync_asignar_rev();
create index if not exists historial_de_precios_rev_idx on historial_de_precios (rev);

create trigger trg_pendientes_rev before insert or update on pendientes
  for each row execute function sync_asignar_rev();
create index if not exists pendientes_rev_idx on pendientes (rev);

create trigger trg_configuracion_negocio_tabla_rev before insert or update on configuracion_negocio_tabla
  for each row execute function sync_asignar_rev();
create index if not exists configuracion_negocio_tabla_rev_idx on configuracion_negocio_tabla (rev);

create trigger trg_medios_de_pago_rev before insert or update on medios_de_pago
  for each row execute function sync_asignar_rev();
create index if not exists medios_de_pago_rev_idx on medios_de_pago (rev);

-- ============================================================
-- RLS: un solo dueño autorizado, mismo criterio que `firestore.rules`
-- ============================================================
alter table usuarios enable row level security;
alter table categorias enable row level security;
alter table proveedores enable row level security;
alter table clientes enable row level security;
alter table productos enable row level security;
alter table sesiones_de_caja enable row level security;
alter table ventas enable row level security;
alter table lineas_de_venta enable row level security;
alter table pagos enable row level security;
alter table movimientos_de_stock enable row level security;
alter table movimientos_de_caja enable row level security;
alter table arqueos_intermedios enable row level security;
alter table historial_de_precios enable row level security;
alter table pendientes enable row level security;
alter table configuracion_negocio_tabla enable row level security;
alter table medios_de_pago enable row level security;
alter table configuracion_cobro enable row level security;

create policy usuarios_solo_autorizado on usuarios
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy categorias_solo_autorizado on categorias
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy proveedores_solo_autorizado on proveedores
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy clientes_solo_autorizado on clientes
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy productos_solo_autorizado on productos
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy sesiones_de_caja_solo_autorizado on sesiones_de_caja
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy ventas_solo_autorizado on ventas
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy lineas_de_venta_solo_autorizado on lineas_de_venta
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy pagos_solo_autorizado on pagos
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy movimientos_de_stock_solo_autorizado on movimientos_de_stock
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy movimientos_de_caja_solo_autorizado on movimientos_de_caja
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy arqueos_intermedios_solo_autorizado on arqueos_intermedios
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy historial_de_precios_solo_autorizado on historial_de_precios
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy pendientes_solo_autorizado on pendientes
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy configuracion_negocio_tabla_solo_autorizado on configuracion_negocio_tabla
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy medios_de_pago_solo_autorizado on medios_de_pago
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

create policy configuracion_cobro_solo_autorizado on configuracion_cobro
  for all
  using (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com')
  with check (auth.jwt() ->> 'email' = 'gtalovergamer@gmail.com');

-- ============================================================
-- Realtime: las 17 tablas, para que el pull en vivo funcione igual en
-- Windows y Android (reemplaza el listener nativo + polling de Firestore).
-- ============================================================
alter publication supabase_realtime add table
  usuarios,
  categorias,
  proveedores,
  clientes,
  productos,
  sesiones_de_caja,
  ventas,
  lineas_de_venta,
  pagos,
  movimientos_de_stock,
  movimientos_de_caja,
  arqueos_intermedios,
  historial_de_precios,
  pendientes,
  configuracion_negocio_tabla,
  medios_de_pago,
  configuracion_cobro;

-- ============================================================
-- Columnas agregadas DESPUÉS de la primera corrida de este archivo. Un
-- proyecto de Supabase ya creado no vuelve a pasar por los `create table`
-- de arriba (`if not exists`), así que cada columna nueva también va acá,
-- idempotente, para correr a mano en el SQL Editor antes de instalar el
-- build que la escribe — si no, PostgREST rechaza el upsert de la fila
-- entera por columna desconocida y esa tabla deja de sincronizar.
-- ============================================================

-- schemaVersion 34 (2026-09-25): excedente de Mercado Pago por cigarrillos.
alter table sesiones_de_caja
  add column if not exists excedente_mp_cigarrillos_generado_centavos bigint;
alter table movimientos_de_caja
  add column if not exists uso_excedente_cigarrillos smallint default 0;

-- 2026-09-26: `sync_asignar_rev` descarta los upserts sin cambios (ver su
-- comentario más arriba). `create or replace` — seguro de volver a correr.
create or replace function sync_asignar_rev() returns trigger as $$
begin
  if tg_op = 'UPDATE' and (to_jsonb(new) - 'rev') = (to_jsonb(old) - 'rev') then
    return null;
  end if;
  new.rev := nextval('sync_rev_seq');
  return new;
end;
$$ language plpgsql;

-- schemaVersion 35 (2026-09-26): parte de lo separado que está en Mercado Pago.
alter table proveedores
  add column if not exists separado_mp_centavos bigint default 0;

-- schemaVersion 38 (2026-09-26): separación del día por proveedor (para poder destildar).
alter table proveedores
  add column if not exists separado_del_dia_fecha bigint,
  add column if not exists separado_del_dia_centavos bigint default 0,
  add column if not exists separado_del_dia_mp_centavos bigint default 0,
  add column if not exists corte_antes_del_dia bigint,
  add column if not exists pendiente_base_antes_del_dia_centavos bigint default 0;
