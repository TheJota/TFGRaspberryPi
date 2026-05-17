# TFG - Sistema de streaming basado en Raspberry Pi

Repositorio del Trabajo Fin de Grado "Sistema de streaming basado en Raspberry Pi" (Jose María León Fernandez, UAM, 2026).

## Estructura

```
web/              -> Aplicacion web remota (Flask + FFmpeg)
scripts/          -> Scripts de medicion de metricas
datos/            -> Datos en bruto de las pruebas (CSV)
```

## Web remota

Interfaz web para controlar la emision en directo desde una Raspberry Pi 5 hacia Twitch mediante FFmpeg.

Ver `web/README.md` para instrucciones de instalacion y uso.

## Scripts de medicion

- `medir_obs.sh` — Recoge metricas del sistema durante una emision con OBS Studio. Usa OBS WebSocket para obtener bitrate, fps y frames skipped.
- `medir_ffmpeg.sh` — Lanza FFmpeg y recoge metricas del sistema durante la emision.

Ambos scripts generan ficheros CSV con muestras cada 5 segundos.

## Datos

La carpeta `datos/` contiene los ficheros CSV con los resultados de todas las repeticiones realizadas durante las pruebas del proyecto.
