#!/bin/bash
# medir_obs.sh - Recoge metricas del sistema durante una emision con OBS
# Usa OBS WebSocket para obtener bitrate, fps y frames skipped
# Uso: ./medir_obs.sh <numero_repeticion>

DURACION=300
INTERVALO=5
HERRAMIENTA="OBS"
REPETICION=${1:-1}
FECHA=$(date +%Y%m%d_%H%M%S)
FICHERO="metricas_${HERRAMIENTA}_rep${REPETICION}_${FECHA}.csv"
WS_URL="ws://localhost:4455"

# Consulta al WebSocket de OBS para sacar las stats del stream
obs_stats() {
    RESPUESTA=$(
        (
            echo '{"op":1,"d":{"rpcVersion":1}}'
            sleep 0.5
            echo '{"op":6,"d":{"requestType":"GetStreamStatus","requestId":"stats"}}'
            sleep 0.5
        ) | timeout 3 websocat -n "$WS_URL" 2>/dev/null | grep '"op":7'
    )

    if [ -z "$RESPUESTA" ]; then
        echo "0 0 0 false"
        return
    fi

    BYTES=$(echo "$RESPUESTA" | grep -oP '"outputBytes":\K[0-9]+' || echo "0")
    FRAMES=$(echo "$RESPUESTA" | grep -oP '"outputTotalFrames":\K[0-9]+' || echo "0")
    SKIPPED=$(echo "$RESPUESTA" | grep -oP '"outputSkippedFrames":\K[0-9]+' || echo "0")
    ACTIVE=$(echo "$RESPUESTA" | grep -oP '"outputActive":\K(true|false)' || echo "false")

    echo "$BYTES $FRAMES $SKIPPED $ACTIVE"
}

echo "Script de medicion - $HERRAMIENTA - Repeticion $REPETICION"
echo "Duracion: ${DURACION}s - Intervalo: ${INTERVALO}s"
echo "Fichero: $FICHERO"
echo ""
echo "Asegurate de que OBS esta emitiendo antes de continuar."
read -p "Pulsa ENTER cuando OBS este en emision activa..."
echo ""

# Comprobar que OBS esta emitiendo
STATS_INIT=$(obs_stats)
ACTIVE_INIT=$(echo "$STATS_INIT" | awk '{print $4}')
if [ "$ACTIVE_INIT" != "true" ]; then
    echo "AVISO: OBS no detecta emision activa."
    read -p "Pulsa ENTER para continuar o Ctrl+C para cancelar..."
fi

echo "Iniciando medicion..."
echo ""

# Cabecera del CSV
echo "timestamp,cpu_percent,ram_mb,temp_c,bitrate_kbps,fps_real,frames_skipped" > "$FICHERO"

MUESTRAS=0
SUM_CPU=0; SUM_RAM=0; SUM_TEMP=0; SUM_BITRATE=0; SUM_FPS=0
MAX_CPU=0; MAX_RAM=0; MAX_TEMP=0; MAX_BITRATE=0
MIN_CPU=999; MIN_RAM=999999; MIN_TEMP=999

BYTES_ANT=0
FRAMES_ANT=0
TIEMPO_ANT=$(date +%s)

INICIO=$(date +%s)
FIN=$((INICIO + DURACION))

while [ $(date +%s) -lt $FIN ]; do
    TIMESTAMP=$(date +%H:%M:%S)
    TIEMPO_ACT=$(date +%s)

    # Metricas del sistema
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | tr -d '%us,')
    RAM=$(free -m | awk '/^Mem:/{print $3}')
    TEMP=$(vcgencmd measure_temp | grep -oP '[0-9]+\.[0-9]+')

    # Metricas de OBS via WebSocket
    STATS=$(obs_stats)
    BYTES_ACT=$(echo "$STATS" | awk '{print $1}')
    FRAMES_ACT=$(echo "$STATS" | awk '{print $2}')
    SKIPPED=$(echo "$STATS" | awk '{print $3}')

    # Calcular bitrate real en kbps
    DELTA_T=$((TIEMPO_ACT - TIEMPO_ANT))
    if [ "$DELTA_T" -gt 0 ] && [ "$BYTES_ACT" -gt "$BYTES_ANT" ]; then
        DELTA_BYTES=$((BYTES_ACT - BYTES_ANT))
        BITRATE=$(echo "scale=0; $DELTA_BYTES * 8 / $DELTA_T / 1000" | bc)
    else
        BITRATE=0
    fi

    # Calcular FPS reales
    if [ "$DELTA_T" -gt 0 ] && [ "$FRAMES_ACT" -gt "$FRAMES_ANT" ]; then
        DELTA_FRAMES=$((FRAMES_ACT - FRAMES_ANT))
        FPS_REAL=$(echo "scale=1; $DELTA_FRAMES / $DELTA_T" | bc)
    else
        FPS_REAL=0
    fi

    BYTES_ANT=$BYTES_ACT
    FRAMES_ANT=$FRAMES_ACT
    TIEMPO_ANT=$TIEMPO_ACT

    echo "$TIMESTAMP,$CPU,$RAM,$TEMP,$BITRATE,$FPS_REAL,$SKIPPED" >> "$FICHERO"

    echo "[$TIMESTAMP] CPU: ${CPU}%  RAM: ${RAM}MB  Temp: ${TEMP}C  Bitrate: ${BITRATE}kbps  FPS: ${FPS_REAL}  Skipped: ${SKIPPED}"

    # Acumular para el resumen
    SUM_CPU=$(echo "$SUM_CPU + $CPU" | bc)
    SUM_RAM=$(echo "$SUM_RAM + $RAM" | bc)
    SUM_TEMP=$(echo "$SUM_TEMP + $TEMP" | bc)
    SUM_BITRATE=$(echo "$SUM_BITRATE + $BITRATE" | bc)
    SUM_FPS=$(echo "$SUM_FPS + $FPS_REAL" | bc)
    MUESTRAS=$((MUESTRAS + 1))

    MAX_CPU=$(echo "if ($CPU > $MAX_CPU) $CPU else $MAX_CPU" | bc)
    MAX_RAM=$(echo "if ($RAM > $MAX_RAM) $RAM else $MAX_RAM" | bc)
    MAX_TEMP=$(echo "if ($TEMP > $MAX_TEMP) $TEMP else $MAX_TEMP" | bc)
    MAX_BITRATE=$(echo "if ($BITRATE > $MAX_BITRATE) $BITRATE else $MAX_BITRATE" | bc)

    MIN_CPU=$(echo "if ($CPU < $MIN_CPU) $CPU else $MIN_CPU" | bc)
    MIN_RAM=$(echo "if ($RAM < $MIN_RAM) $RAM else $MIN_RAM" | bc)
    MIN_TEMP=$(echo "if ($TEMP < $MIN_TEMP) $TEMP else $MIN_TEMP" | bc)

    sleep $INTERVALO
done

# Resumen
MEDIA_CPU=$(echo "scale=1; $SUM_CPU / $MUESTRAS" | bc)
MEDIA_RAM=$(echo "scale=0; $SUM_RAM / $MUESTRAS" | bc)
MEDIA_TEMP=$(echo "scale=1; $SUM_TEMP / $MUESTRAS" | bc)
MEDIA_BITRATE=$(echo "scale=0; $SUM_BITRATE / $MUESTRAS" | bc)
MEDIA_FPS=$(echo "scale=1; $SUM_FPS / $MUESTRAS" | bc)

echo ""
echo "RESUMEN - $HERRAMIENTA - Repeticion $REPETICION"
echo "Muestras: $MUESTRAS"
echo "CPU     -> Media: ${MEDIA_CPU}%  Min: ${MIN_CPU}%  Max: ${MAX_CPU}%"
echo "RAM     -> Media: ${MEDIA_RAM}MB  Min: ${MIN_RAM}MB  Max: ${MAX_RAM}MB"
echo "Temp    -> Media: ${MEDIA_TEMP}C  Min: ${MIN_TEMP}C  Max: ${MAX_TEMP}C"
echo "Bitrate -> Media: ${MEDIA_BITRATE}kbps  Max: ${MAX_BITRATE}kbps"
echo "FPS     -> Media: ${MEDIA_FPS}"

echo "" >> "$FICHERO"
echo "# RESUMEN" >> "$FICHERO"
echo "# Muestras,$MUESTRAS" >> "$FICHERO"
echo "# CPU_media,$MEDIA_CPU" >> "$FICHERO"
echo "# CPU_min,$MIN_CPU" >> "$FICHERO"
echo "# CPU_max,$MAX_CPU" >> "$FICHERO"
echo "# RAM_media,$MEDIA_RAM" >> "$FICHERO"
echo "# RAM_min,$MIN_RAM" >> "$FICHERO"
echo "# RAM_max,$MAX_RAM" >> "$FICHERO"
echo "# Temp_media,$MEDIA_TEMP" >> "$FICHERO"
echo "# Temp_min,$MIN_TEMP" >> "$FICHERO"
echo "# Temp_max,$MAX_TEMP" >> "$FICHERO"
echo "# Bitrate_media,$MEDIA_BITRATE" >> "$FICHERO"
echo "# Bitrate_max,$MAX_BITRATE" >> "$FICHERO"
echo "# FPS_media,$MEDIA_FPS" >> "$FICHERO"

echo ""
echo "Datos guardados en: $FICHERO"
