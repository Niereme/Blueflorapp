# Sistema visual — Fase 2.1

La fuente del tema es `lib/presentation/design/blueflora_theme.dart`.
`main.dart` selecciona sus variantes con la preferencia existente; no cambia
el almacenamiento ni los controladores. Esta fase aplica solo estilos globales.
Los colores locales antiguos de las pantallas se revisarán en la Fase 2.2.

## Tokens y decisiones

- Referencia de marca: verde `#4CAF7D`.
- Acciones: verde `#246342` con blanco en claro; `#8BD5AC` con `#103822`
  en oscuro. La referencia original no tiene suficiente contraste con blanco
  para textos pequeños.
- Superficie: crema `#FFF9EF` / oscuro `#141D18`.
- Texto principal: `#293D32` / `#E1EADF`.
- Contenedor principal y éxito: menta `#DDF5E5` / `#234C36`.
- Advertencia: `#FFD978` / `#514219`; siempre con texto e icono.
- Error y superficies secundarias: roles semánticos Material 3 derivados del verde.
- Espaciados: 8, 16 y 24 dp; radio de tarjeta/botón: 18 dp; campos: 16 dp.
- Tipografía Material del dispositivo, sin descargar fuentes: títulos semibold,
  cuerpo con interlineado 1.45, botones de 16 sp. No se limita el escalado.
- Botones de al menos 48 dp, padding vertical 12 y horizontal 24; altura flexible.
- Tarjetas con elevación 1 y sombra de opacidad 12%.
- Transiciones de 160 ms. Los componentes animados y el cambio de tema respetan
  movimiento reducido; el indicador compartido muestra progreso estático en ese modo.

## Componentes

`flora_components.dart` ofrece `FloraInfoCard`, `FloraSectionHeading`,
`FloraStatusLabel`, `FloraMessage` y `FloraLoading`. Son exclusivamente visuales:
el consumidor determina el estado y los mensajes, sin reglas de riego internas.
Usar `FilledButton` para acción principal, `OutlinedButton` para secundaria y
`TextButton` para acciones terciarias; sus estilos se centralizan en el tema,
sin envoltorios redundantes. Usar iconos Material outlined en nuevos componentes.

Los estados consumen `FloraStatusColors`, una extensión del tema. No introducir
hexadecimales en las pantallas para reproducir estos estados. Los contenedores
no fijan alturas ni truncan textos. Colocar bloques extensos en superficies
desplazables y etiquetas de estado dentro de un ancho acotado.

## Validación y límites

Las pruebas verifican contraste mínimo 4.5:1 para los pares principales y estados
en ambos temas, texto al 200% con ancho de 320 dp, tamaño de botones y movimiento
reducido. Las pruebas de preferencias existentes comprueban claro/oscuro/sistema
y persistencia. Estas verificaciones no sustituyen la revisión visual con
TalkBack, tamaños de fuente del teléfono y brillo real de pantalla.
