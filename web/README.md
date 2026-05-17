# Web Remota - Streaming Pi

Web para controlar el streaming desde la Raspberry Pi 5 a Twitch con FFmpeg.

## Como usar

Instalar dependencias:
```
sudo apt install python3 python3-pip ffmpeg v4l-utils -y
pip3 install flask psutil --break-system-packages
```

Ejecutar:
```
python3 app.py
```

Acceder desde el navegador a `http://<IP_raspberry>:5000`, meter la Stream Key y darle a Iniciar.

## Archivos

- `app.py` — servidor Flask
- `templates/index.html` — interfaz
- `static/` — logo UAM
- `config.json` — configuracion por defecto
