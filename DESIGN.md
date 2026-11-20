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
