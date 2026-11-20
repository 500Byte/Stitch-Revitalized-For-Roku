# Stitch Revitalized for Roku — Design System (10-Foot UI)

> Guía de diseño, tokens, ergonomía y componentes para la experiencia de salón (Roku TV / 10-foot experience).

---

## 1. Ergonomía & Espacio de Coordenadas

- **Espacio Fijo de Diseño:** `1920 × 1080` (Full HD).
  - Roku escala automáticamente al plano físico del dispositivo (`1280x720` en HD / `3840x2160` en 4K). Nunca utilices `GetUIResolution().width` para cálculos de layout en código; asume siempre 1920×1080.
- **TV Safe Zone (Overscan):**
  - Margen horizontal mínimo: `60px` (elementos interactivos entre `x: 60` y `x: 1860`).
  - Margen vertical mínimo: `50px` (elementos interactivos entre `y: 50` y `y: 1030`).
- **Sistema de Espaciado (Múltiplos de 8px):**
  - `xs`: 8px
  - `sm`: 16px
  - `md`: 24px
  - `lg`: 32px
  - `xl`: 48px
  - `2xl`: 64px

---

## 2. Tokens de Color Semánticos

Los colores están disponibles globalmente en `m.global.constants.colors.semantic`:

| Token | Hex RGBA | Uso en Interfaz |
|---|---|---|
| `bgCanvas` | `0x0E0E10FF` | Fondo maestro de la app (Twitch Obsidian) |
| `bgSurface` | `0x18181BFF` | Paneles, cards de stream, filas y cajas de control |
| `bgOverlay` | `0x1F1F23EE` | Modales, HUDs flotantes, chat overlay |
| `bgDialog` | `0x18181BFA` | Cuadros de diálogo y menús modales |
| `focusRing` | `0x9146FFFF` | Borde y realce de foco activo (Twitch Purple) |
| `accentLive` | `0xEB0400FF` | Badge "LIVE" y badges de emisión en directo |
| `accentMute` | `0xE91E63FF` | Tramos silenciados en seekbar y botón de salto |
| `textPrimary` | `0xFFFFFFFF` | Títulos, foco, mensajes principales |
| `textSecondary`| `0xADADB8FF` | Metadatos, uptime, nombres de canal secundarios |
| `textMuted` | `0x53535FFF` | Timestamps, textos secundarios deshabilitados |

---

## 3. Tipografía (10-Foot Safe)

Fuentes del paquete: `pkg:/fonts/Archivo-Bold.otf` y `pkg:/fonts/Archivo-Regular.otf`.

> [!IMPORTANT]
> **Regla de oro TV:** Ningún texto legible debe medir menos de 16px. A 3 metros de distancia, fuentes de 12-14px provocan fatiga visual.

| Nivel | Tamaño | Peso / Fuente | Aplicación |
|---|---|---|---|
| **Display / Hero** | `36px - 44px` | Archivo-Bold | Título de stream en overlay / headers |
| **Section Header** | `26px - 28px` | Archivo-Bold | Títulos de fila (Browse, Following, Settings) |
| **Body / Action** | `20px - 22px` | Archivo-Bold / Regular | Botones, toasts, nombres en chat |
| **Caption / Badge** | `16px - 18px` | Archivo-Bold | Badges [OK], LIVE, Uptime, duración |

---

## 4. Componentes Estándar

### A. Botón de Acción Flotante (Action Pill / Netflix-Style)
- **Dimensiones:** `360 × 52 px`.
- **Fondo:** `0x18181BF0` con acento lateral de `6px` (`accentLive` o `accentMute`).
- **Badge D-Pad:** Recuadro `48 × 30 px` con texto blanco `"OK"`.
- **Texto:** `20px` Archivo-Bold con alineación vertical centrada.

### B. Toasts del Reproductor (HUD)
- **Ubicación:** `y: 60`, centrado en pantalla (`translation: [820, 60]`).
- **Fondo:** `0x000000D0` (o `accentMute` en avisos de silencio).
- **Duración:** 2 a 3 segundos con timer SceneGraph no bloqueante.

### C. Chat en Reproductor (3 Modos)
1. **Sidebar (`mode: 1`):** Ancho configurable (400px - 576px / 30vw). Fondo sólido negro (`1.0`). El vídeo reduce su ancho a la izquierda sin superposición.
2. **Superpuesto / Overlay (`mode: 2`):** Vídeo a pantalla completa. Chat flotando a la derecha con fondo semitransparente (`0.65`).
3. **Oculto (`mode: 0`):** Chat apagado. Vídeo a pantalla completa.

---

## 5. Algoritmo de Colores Legibles (FrankerFaceZ / WCAG)

Para nombres de usuario en el chat:
1. Si el usuario no tiene color configurado en Twitch, se selecciona un color pastel predeterminado mediante hash determinista de su `display_name`.
2. Se calcula la luminancia perceptual:
   $$Y = 0.299 \times R + 0.587 \times G + 0.114 \times B$$
3. Si $Y < 115$ (color demasiado oscuro para fondo negro), se aclara proporcionalmente preservando el tono cromático original:
   $$\text{ratio} = \frac{115 - Y}{160}$$
   $$C' = C + (255 - C) \times \text{ratio}$$

---

## 6. Arquitectura del Reproductor (Modern Floating HUD - Punto Medio LG + Apple TV)

El reproductor adopta una arquitectura inspirada en lo mejor de la app oficial de Twitch para **LG TV** (anclaje de metadatos inferior y seekbar corrida) y **Apple TV** (cápsulas estilizadas tipo tvOS y ergonomía de 10 pies sin obstrucción central):

### A. Zona Superior (Minimal Status)
- **Coordenadas:** `translation: [0, 48]`. La zona superior se mantiene 100% limpia del título/streamer para permitir máxima visibilidad del contenido.
- **Top Scrim:** Gradiente sutil `1920 × 180px` (`pkg:/images/scrim_top.png`).
- **Badges de Estado (Esquina Superior Derecha):**
  - `[ LIVE | 01:26:31 ]`: Cápsula `0x18181BE6` de 36px de altura con badge rojo `0xEB0400FF` y uptime dinámico en directos.

### B. Barra de Progreso y Tiempo (LG TV Scrub Bar)
- **Coordenadas:** `translation: [70, 835]`.
- **Bottom Scrim:** Gradiente cinematográfico `1920 × 340px` (`pkg:/images/scrim_bottom.png`) a partir de Y=740.
- **Seekbar:**
  - Ancho completo: `1780 × 8px` (base `0x3A3A3DFF`, buffer `0x53535FFF`, progreso Twitch Purple `0x9146FFFF`).
  - Tramos silenciados (VOD): Dual-blend segmentado (coral `#BA4D5E` no visto / rosa neón `#EA428D` visto).
  - Progress Dot: `22 × 22px` con núcleo blanco de `10 × 10px`.
- **Timestamps:**
  - Izquierda: `timeProgress` (`00:48`) en `Archivo-Bold` 18px blanco (`0xFFFFFFFF`).
  - Derecha: `timeDuration` (`02:15:33`) en `Archivo-Bold` 18px gris (`0xADADB8FF`).

### C. Fila Inferior (LG TV Metadata + Apple TV Pills)
Directamente debajo de la seekbar (Y ~ 890px), la fila inferior se divide en dos bloques equilibrados:
1. **Bloque Izquierdo (Metadatos del Canal):**
   - **Avatar:** `CirclePoster` `60 × 60px` (`translation: [0, 0]`).
   - **Streamer Name:** `Archivo-Bold.otf` 22px blanco (`translation: [76, 4]`).
   - **Stream/VOD Title:** `EmojiLabel` con `Archivo-Regular.otf` 16px gris (`0xADADB8FF`, `translation: [76, 34]`, soporte completo de emojis y truncado elíptico).
2. **Bloque Derecho (Cápsulas de Acción):**
   - **VOD:**
     - Transporte: `[ ↺ -10s ]` (`76 × 56px`), `[ ▶ / ⏸ Hero ]` (`92 × 64px`, foco inicial por defecto), `[ ↻ +10s ]` (`76 × 56px`).
     - Utilidades: `[ ⏱ Time Travel ]` (`64 × 56px`), `[ 💬 Modo Chat ]` (`72 × 56px`), `[ ⚙ Ajustes / Calidad ]` (`64 × 56px`).
   - **Directos (Live):**
     - `[ ▶ / ⏸ Hero ]` (`92 × 64px`), `[ 💬 Modo Chat ]` (`72 × 56px`), `[ ⚙ Ajustes / Calidad ]` (`64 × 56px`).

### D. Responsividad con Chat Sidebar (Drawer Derecho ~26%)
- Al abrirse el chat lateral (`495px` de ancho en 1080p, equivalente a LG TV):
  - El ancho de la seekbar se ajusta de 1780px a `videoWidth - 115px` (~1310px).
  - El cluster de botones se desplaza a la derecha del área de video visible (`translation: [videoWidth - 45 - buttonsW, 890]`).
  - `maxWidth` del título se recalcula dinámicamente (`buttonsX - 176px`) evitando cualquier solapamiento.
  - El badge `LIVE` se alinea a `[videoWidth - 270, 48]`.

---

## 7. Vistas de Navegación, Tarjetas y Utilidades (Estilo LG TV)

Las pantallas fuera del reproductor heredan los mismos tokens, márgenes TV (`1920 × 1080`) y tipografía `Archivo` del módulo de reproducción:

- **Barra superior (`MenuBar`, `80px`):** Fondo `0x121215FF`, divisor `1px` `0x26262CFF`, badge de marca `"S"` morado (`[20, 21]`), pestañas en `24px Archivo-Bold` (`textSecondary` -> `textPrimary` + subrayado morado) e iconos Lucide de `32px` con margen derecho de safe-zone `60px` (y avatar de usuario sin tintado a `36px`).
- **Sidebar lateral (`RecentlyWatchedBar`, `78px × 1000px` debajo del header):** Fondo `0x121215FF` + borde derecho `1px` `0x26262CFF`, `54px` avatares en paso vertical `68px` y tooltip flotante (`capsule.9.png`, `18px Archivo-Bold`) mostrando el nombre del canal enfocado y su estado `LIVE`.
- **Home (`Following`, Hero Spotlight + Estantes Horizontales):**
  - Zona Hero superior (`380px`, `heroBackdrop` atenuado + scrims superior/inferior) actualizada con debounce `0.15s` según el elemento enfocado: pill `LIVE` adaptativa, streamer (`24px Archivo-Bold`), categoría · espectadores (`20px Archivo-Regular`) y título completo a 2 líneas (`36px Archivo-Bold`).
  - Carruseles horizontales continuos: seguidos en vivo, hasta 4 filas recomendadas (sin shelves `GAME`) y seguidos sin conexión en una fila horizontal debajo (`translation: [104, 424]`, `numRows="2"`).
- **Tarjetas y RowList (`VideoItem` + `contentBuilder`):**
  - Miniatura `400 × 225px` (16:9, resuelta vía `formatTwitchImageUrl()` en `640×360` para VODs/clips), badge `LIVE` en cápsula roja con ancho medido dinámicamente (`16px Archivo-Bold`), píldoras de viewers / fecha relativa en cápsula oscura (`16px Archivo-Bold`).
  - Fila inferior con avatar circular `48 × 48px` (cuando existe `streamerProfileImageUrl`) y jerarquía a 3 líneas: título en `20px Archivo-Bold`, streamer en `18px Archivo-Regular` (`0xDEDEE3FF`) y categoría en `17px Archivo-Regular` (`textSecondary`). Los títulos de `GAME` y `USER` usan `Label` nativo (`plainTitle`, `20px Archivo-Bold`) para evitar clipping.
  - Encabezados de sección unificados vía `styleRowListHeader()` (`28px Archivo-Bold` blanco, offset `[0, 14]`).
- **Vistas secundarias:**
  - `ChannelPage`: Banner `1920 × 260px` con scrim inferior, avatar `136 × 136px` (`width: 300`), cápsula `LIVE` (`96×28px`), bio en tarjeta custom (`0x18181BE6`, `20px`, máximo 3 líneas) y grillas dentro de safe-zone `64px`.
  - `GamePage`: Cabecera `176px` (`0x141418FF`) con carátula `84 × 112px`, título `40px Archivo-Bold` y subtítulo de audiencia (`20px`).
  - `Settings`, `Search`, `LoginPage`: Tarjetas `0x18181BFF` con bordes `0x26262CFF`, foco en cápsula `0x9146FFFF`, tipografía mínima `18-20px Archivo` y marco blanco de alto contraste para el QR de activación (`LoginPage`).

