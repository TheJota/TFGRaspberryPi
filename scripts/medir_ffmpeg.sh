#!/bin/bash
# medir_ffmpeg.sh - Lanza FFmpeg y recoge metricas del sistema
# Uso: ./medir_ffmpeg.sh <numero_repeticion> <stream_key>
# Ejemplo: ./medir_ffmpeg.sh 1 live_XXXX_YYYYYYY

REPETICION=${1:-1}
STREAM_KEY=${2:-"TEST"}
DURACION=300
INTERVALO=5
SALIDA="ffmpeg_rep${REPETICION}.csv"
LOG_FFMPEG="/tmp/ffmpeg_rep${REPETICION}.log"
RTMP_URL="rtmp://live.twitch.tv/app/${STREAM_KEY}"

echo "medir_ffmpeg.sh - Repeticion ${REPETICION}"
echo "Duracion: ${DURACION}s | Intervalo: ${INTERVALO}s"
echo "Salida CSV: ${SALIDA}"
echo ""

# Cabecera CSV
echo "timestamp,elapsed_s,cpu_percent,ram_mb,temp_c,bitrate_kbps,fps" > "$SALIDA"

> "$LOG_FFMPEG"

echo "Lanzando FFmpeg..."

ffmpeg \
  -thread_queue_size 512 \
  -f v4l2 -input_format mjpeg -video_size 1280x720 -framerate 30 \
  -i /dev/video0 \
  -thread_queue_size 512 \
  -f alsa -i default \
  -c:v libx264 -preset veryfast \
  -b:v 2500k -minrate 2500k -maxrate 2500k -bufsize 5000k \
  -pix_fmt yuv420p -g 60 \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "$RTMP_URL" \
  2>"$LOG_FFMPEG" &

FFMPEG_PID=$!
echo "FFmpeg PID: ${FFMPEG_PID}"
echo ""

# Esperar a que la webcam se estabilice antes de medir
echo "Esperando estabilizacion de la webcam (15s)..."
sleep 15

if ! kill -0 "$FFMPEG_PID" 2>/dev/null; then
  echo "ERROR: FFmpeg termino inesperadamente."
  tail -20 "$LOG_FFMPEG"
  exit 1
fi

echo "FFmpeg activo. Midiendo..."
echo ""

# Sacar numero de frames del log de FFmpeg
get_frame_count() {
  cat "$LOG_FFMPEG" 2>/dev/null \
    | tr '\r' '\n' \
    | grep -oP 'frame=\s*\K[0-9]+' \
    | tail -1
}

# Sacar bitrate del log de FFmpeg
get_bitrate() {
  cat "$LOG_FFMPEG" 2>/dev/null \
    | tr '\r' '\n' \
    | grep -oP 'bitrate=\s*\K[0-9.]+(?=kbits)' \
    | tail -1
}

ELAPSED=0
FRAMES_ANTERIOR=0

while [ "$ELAPSED" -lt "$DURACION" ]; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

  CPU=$(top -bn2 -d0.5 | grep "^%Cpu" | tail -1 | awk '{printf "%.1f", 100 - $8}')
  RAM=$(free -m | awk '/^Mem:/{print $3}')
  TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oP '[0-9]+\.[0-9]+' || echo "N/A")

  BITRATE=$(get_bitrate)
  [ -z "$BITRATE" ] && BITRATE="N/A"

  # FPS = (frames ahora - frames antes) / intervalo
  FRAMES_AHORA=$(get_frame_count)
  [ -z "$FRAMES_AHORA" ] && FRAMES_AHORA=0

  if [ "$ELAPSED" -eq 0 ] || [ "$FRAMES_ANTERIOR" -eq 0 ]; then
    FPS="N/A"
  else
    DELTA=$((FRAMES_AHORA - FRAMES_ANTERIOR))
    if [ "$DELTA" -lt 0 ] || [ "$DELTA" -gt 300 ]; then
      FPS="N/A"
    else
      FPS=$(awk "BEGIN {printf \"%.1f\", $DELTA / $INTERVALO}")
    fi
  fi
  FRAMES_ANTERIOR=$FRAMES_AHORA

  # Comprobar que FFmpeg sigue corriendo
  if ! kill -0 "$FFMPEG_PID" 2>/dev/null; then
    echo "AVISO: FFmpeg termino en el segundo ${ELAPSED}s"
    echo "${TIMESTAMP},${ELAPSED},${CPU},${RAM},${TEMP},${BITRATE},${FPS}" >> "$SALIDA"
    break
  fi

  echo "${TIMESTAMP},${ELAPSED},${CPU},${RAM},${TEMP},${BITRATE},${FPS}" >> "$SALIDA"

  printf "[%s] t=%3ds | CPU=%5s%% | RAM=%4s MB | Temp=%sC | Bitrate=%s kbps | FPS=%s\n" \
    "$TIMESTAMP" "$ELAPSED" "$CPU" "$RAM" "$TEMP" "$BITRATE" "$FPS"

  sleep "$INTERVALO"
  ELAPSED=$((ELAPSED + INTERVALO))
done

# Parar FFmpeg
echo ""
echo "Tiempo completado. Parando FFmpeg..."
kill "$FFMPEG_PID" 2>/dev/null && wait "$FFMPEG_PID" 2>/dev/null || true

echo ""
echo "Repeticion ${REPETICION} finalizada"
echo "CSV: ${SALIDA} ($(wc -l < "$SALIDA") lineas)"
echo ""
echo "Vista previa:"
cat "$SALIDA"
