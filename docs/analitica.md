# Analítica de partidas

Este documento explica qué mide el juego, dónde lo guarda y cómo leerlo. Todo se guarda en local. Además, cada nivel terminado se sube al servidor de estadísticas local (`server/`) cuando está corriendo: ver [Subida al servidor](#subida-al-servidor).

## Perfiles y tiempo jugado

- El menú principal muestra el perfil activo y su tiempo total jugado.
- **Cambiar perfil:** abre la pantalla para elegir, crear o borrar perfiles. Borrar pide un segundo clic. Un perfil es solo un nombre o apodo.
- **Continuar:** retoma la partida guardada del perfil, con nivel, vidas, arma, semilla, monedas y mejoras. La partida se guarda al empezar cada nivel en modo normal, y morir la borra.
- **Tiempo:** se suma solo el tiempo sin pausa. Se guarda al terminar un nivel, al morir, al volver al menú y al cerrar la ventana.
- El nombre del antiguo `player.cfg` se convierte en el primer perfil, una sola vez.

## Telemetría

- El autoload `Telemetry` registra, mientras se juega:
  - La posición del jugador, cada 0,25 s o cuando se mueve más de 8 px.
  - Estos eventos, con su posición y su tiempo: daño recibido (con su fuente), enemigo eliminado, corazón, llave, puerta (cerrada o escape), ataque (acertado o fallado), cambio de arma, muerte (con su causa) y reaparición (demo).
- Todo queda en memoria durante el nivel. Se escribe al disco solo al completarlo, al morir o al abandonarlo.
- **Ajustes › Telemetría** la desactiva. Viene activada. Desactivada, no se graba ni se sube nada y no hay minimapa ni resumen de la partida; el tiempo jugado y la partida guardada siguen funcionando.

### Dónde se guarda

| Ruta | Contenido |
|---|---|
| `user://profiles/<perfil>/profile.json` | Nombre, tiempo total y partida guardada |
| `user://profiles/<perfil>/runs/<run_id>/level_<n>.json` | Un nivel jugado: mapa, recorrido y eventos. Si un nivel se repite en la misma partida, queda como `level_<n>_<k>.json` |
| `user://analytics/` | Exportaciones: CSV, `insights.md` y el paquete de `export_all()` |
| `user://settings.cfg` | Ajustes, incluida la telemetría |
| `user://level_uploads.json` | Niveles pendientes de subir al servidor |

- En Linux, `user://` es `~/.local/share/godot/app_userdata/New Game Project/`.
- Cada JSON de nivel incluye `schema_version` y `game_version`. Si a un archivo viejo le faltan campos, `TelemetryStore` usa valores por defecto.
- `TelemetryStore.export_all()` junta todas las partidas en un solo archivo, para compartirlas con el equipo.

### Subida al servidor

- `LevelUploader` sube cada JSON de nivel tal cual a `POST /api/runs/<partida>/levels`. La página web del servidor los usa para el recorrido y los mapas de calor.
- `<partida>` es la del servidor, la que crea `RunTracker`. No es el `run_id` del archivo, que es la carpeta local.
- **Orden:** un nivel se sube recién cuando su partida ya existe en el servidor, es decir, cuando la cola de eventos de `RunTracker` ya envió su inicio.
- **Sin servidor:** los pendientes quedan en `user://level_uploads.json`, aparte de la cola de eventos. Se reintentan cada 2 s y el doble en cada fallo, hasta 60 s, también después de cerrar y abrir el juego.
- **Repetidos:** el servidor guarda una sola vez cada partida, nivel e intento, así reenviar un archivo no lo duplica.
- **Descartes:** un archivo borrado, uno rechazado por el servidor (por ejemplo, 422) o uno cuya partida nunca llegó (404) sale de la lista con un aviso.
- **Telemetría desactivada:** no se sube nada. Lo pendiente se sube al volver a activarla.
- La demo y el modo prueba se suben como cualquier partida, con su `mode`.

## Resumen de la partida

- **Cuándo aparece:** se abre solo al morir o al superar un nivel, encima de la pantalla final. También se abre con el botón «Ver recorrido». «Continuar» o Esc lo cierran.
- **Mapa:**
  - Suelo en gris claro y paredes en gris oscuro.
  - La ruta cambia de color con el tiempo: azul al inicio, amarillo a la mitad y rojo al final.
- **Íconos:**
  - Calavera: muerte.
  - X roja: daño.
  - Llave y puerta.
  - Rombo naranja: enemigo eliminado.
  - Corazón.
  - Círculo celeste: cambio de arma.
  - Anillo verde: reaparición.
- **Puerta:** el borde es naranja si se tocó sin llave y verde si el jugador escapó.
- **Reproducción:** el deslizador recorre la partida y el punto blanco es el jugador en ese instante. «Reproducir» anima el recorrido en unos 12 s.
- **Panel lateral:** tiempo, daño por fuente, enemigos eliminados, corazones, golpes acertados y armas.

## Minimapa

- Está arriba a la derecha durante el juego.
- Muestra las zonas exploradas, el camino recorrido en amarillo y la posición actual.
- La puerta y la llave aparecen solo después de verlas.

## AnalyticsReport (para el equipo)

- **Cómo abrirlo:** con el botón «Analítica» del menú principal. Solo aparece en el editor y en builds de depuración. «Recargar» vuelve a leer las partidas.
- **Qué lee:** todas las partidas guardadas en `user://profiles/`.
- **Filtros:** perfil, nivel, versión del juego y modo.
- **Capas:** tiempo, daño recibido, muertes o enemigos eliminados.
  - El tiempo pesa cada posición por los segundos que el jugador estuvo ahí.
  - El daño suma las vidas perdidas.
  - Las eliminaciones se marcan donde murió el enemigo.
- **Vista «Mismo mapa»:**
  - Agrupa las partidas jugadas sobre el mismo mapa y dibuja el mapa de calor encima. Los niveles generados coinciden si tienen la misma semilla; el nivel 1, hecho a mano, coincide siempre.
  - Letras: I = inicio, L = llave, P = puerta.
  - Color de azul (poco) a rojo (mucho). Al pasar el mouse por una celda se ve su valor.
- **Vista «Sin mapa»:**
  - Junta partidas de cualquier mapa, así sirve para comparar niveles con semillas distintas.
  - Muestra barras por distancia caminando, en celdas, a la puerta y a la llave.
  - También muestra barras por tipo de sala: la de la puerta, la de la llave, la de inicio, otra sala o pasillo.
- **Panel «Avisos»:** muestra los avisos automáticos de los niveles filtrados.

## Avisos automáticos

- Son reglas simples. Los umbrales están al principio de `scripts/analytics/insights.gd`.
- Un nivel recibe avisos solo con al menos 5 intentos.
- **Reglas:**
  - Muertes ≥ 40 %. Se nombra la causa principal si explica ≥ 50 %.
  - Abandonos ≥ 40 %.
  - Tiempo medio ≥ 2,5× el del nivel anterior.
  - Daño por minuto ≥ 2× el del nivel anterior.
- **Ejemplos:** «Nivel 7: 50 % muere, el 80 % por picos» y «Nivel 7: tiempo medio 3× el del nivel 6».
- Se muestran en `AnalyticsReport` y se guardan en `user://analytics/insights.md`.

## DifficultyReport y gráfica de dificultad

- Se abre desde Menú › Modo prueba. A la derecha está la gráfica «Dificultad por nivel: planificada y medida».
- **Línea azul discontinua:** índice planificado (`DifficultyCurve.index_for`), dividido por su máximo en el rango mostrado. El nivel 1 no tiene valor porque está hecho a mano.
- **Línea naranja continua:** dificultad medida.
  - Fórmula: 50 % muertes por intento + 50 % daño por minuto. Cada término se divide por su máximo entre los niveles jugados, así que el nivel más difícil vale 1.
  - Es relativa a los datos analizados y no incluye la demo.
- **Puntos y cortes:** un punto hueco indica menos de 5 intentos, un dato poco fiable. Los niveles sin partidas cortan la línea.
- **Cómo leerla:**
  - Si la naranja sube más que la azul, el nivel es más difícil de lo planeado.
  - Si la naranja baja mientras la azul sube, es más fácil de lo planeado.
- En modo prueba, `difficulty_playtest.csv` suma las columnas `damage_per_min`, `damage_sources` y `death_cause`.

## Exportar a CSV

El botón «Exportar análisis» de `DifficultyReport` escribe en `user://analytics/`:

| Archivo | Contenido |
|---|---|
| `levels.csv` | Por nivel: intentos, muertes, % que completa, tiempo medio, daño por minuto, una columna `damage_<fuente>` por fuente, armas usadas, dificultad medida e índice planificado |
| `deaths.csv` | Una fila por muerte: causa y posición, en px y en celda |
| `runs.csv` | Una fila por partida |
| `insights.md` | Los avisos automáticos |

- **Formato:** UTF-8 con BOM, separador coma y decimales con punto.
- **En un Excel en español:** importar con Datos › Desde texto/CSV y elegir la coma como separador.
- **La demo:** queda fuera de las estadísticas por nivel. Sí aparece en `deaths.csv` y `runs.csv`, donde la columna `mode` la distingue.
