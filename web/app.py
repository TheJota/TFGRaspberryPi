from flask import Flask, render_template, request, jsonify
import subprocess
import psutil
import time

app = Flask(__name__)

ffmpeg_process = None


def build_ffmpeg_command(config):
    return [
        "ffmpeg",
        "-thread_queue_size", "512",
        "-f", "v4l2",
        "-input_format", "mjpeg",
        "-video_size", config["resolution"],
        "-framerate", "30",
        "-i", "/dev/video0",
        "-thread_queue_size", "512",
        "-f", "alsa",
        "-i", "default",
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-b:v", config["bitrate"] + "k",
        "-minrate", config["bitrate"] + "k",
        "-maxrate", config["bitrate"] + "k",
        "-bufsize", str(int(config["bitrate"]) * 2) + "k",
        "-pix_fmt", "yuv420p",
        "-g", "60",
        "-c:a", "aac",
        "-b:a", "128k",
        "-ar", "44100",
        "-f", "flv",
        config["rtmp_url"] + "/" + config["stream_key"]
    ]


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/start", methods=["POST"])
def start():
    global ffmpeg_process
    if ffmpeg_process and ffmpeg_process.poll() is None:
        return jsonify({"status": "already_running"})

    config = request.json

    subprocess.run(
        ["v4l2-ctl", "-d", "/dev/video0", "--set-ctrl=exposure_dynamic_framerate=0"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    time.sleep(2)

    cmd = build_ffmpeg_command(config)
    log = open("ffmpeg.log", "w")
    ffmpeg_process = subprocess.Popen(
        cmd,
        stdout=log,
        stderr=log,
        start_new_session=True
    )
    return jsonify({"status": "started"})


@app.route("/stop", methods=["POST"])
def stop():
    global ffmpeg_process
    if ffmpeg_process and ffmpeg_process.poll() is None:
        ffmpeg_process.terminate()
        ffmpeg_process = None
        return jsonify({"status": "stopped"})
    return jsonify({"status": "not_running"})


@app.route("/stats")
def stats():
    global ffmpeg_process
    running = ffmpeg_process is not None and ffmpeg_process.poll() is None

    temp = psutil.sensors_temperatures()
    cpu_temp = 0.0
    for key in temp:
        cpu_temp = temp[key][0].current
        break

    return jsonify({
        "running": running,
        "cpu": psutil.cpu_percent(interval=1),
        "ram": psutil.virtual_memory().percent,
        "temp": round(cpu_temp, 1)
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
