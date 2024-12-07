from flask import Flask, render_template, Response, request
from time import sleep
import cv2
from multiprocessing import Process, Value, Lock, Queue
import threading
import pygame
import socket

import pyaudio
import os

app = Flask(__name__)

# 서버의 소켓 설정
SOCKET_HOST = '127.0.0.1'  # 로컬호스트
SOCKET_PORT = 65432        # C 서버가 대기 중인 포트

# 업로드 경로 설정
file_path = "C:\\file\\uploads"
os.makedirs(file_path, exist_ok=True)

# 최대 업로드 크기 설정 (예: 50MB)
app.config['MAX_CONTENT_LENGTH'] = 10 * 1024 * 1024  # 50MB

FORMAT = pyaudio.paInt16
CHANNELS = 2
RATE = 44100
CHUNK = 1024
RECORD_SECONDS = 5

audio1 = pyaudio.PyAudio()

capture = None
stream = None

frame_queue = Queue(maxsize=10)
streaming_video = Value('b', False)

audio_queue = Queue(maxsize=200)  # 오디오 데이터를 전달하기 위한 큐
stream_audio_queue = Queue(maxsize=100)
streaming_audio = Value('b', False)  # 오디오 스트리밍 상태 플래그
audio_process = None  # 오디오 처리 프로세스

lock = Lock()  # 스레드 안전성을 위해 Lock 객체 생성


def stream_worker(streaming, frame_queue):
    """웹캠 스트리밍 작업을 실행하는 프로세스."""
    global capture
    capture = cv2.VideoCapture(0)  # 웹캠 객체 생성
    capture.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    while streaming.value:
        ref, frame = capture.read()
        if not ref:
            break
        else:
            if not frame_queue.full():
                ref, buffer = cv2.imencode('.jpg', frame)
                frame_queue.put(buffer.tobytes())  # 큐에 프레임 추가
        sleep(0.1)  # 프레임 생성 간격

    capture.release()


def generate_frames(frame_queue):
    """큐에서 프레임을 읽어 Flask에 전달."""
    while streaming_video.value:
        if not frame_queue.empty():
            frame = frame_queue.get()
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
        else:
            sleep(0.1)  # 큐가 비었을 때 대기


@app.route('/stream')
def stream():
    with lock:
        if not streaming_video.value:
            streaming_video.value = True
            process = Process(target=stream_worker, args=(streaming_video, frame_queue))
            process.start()
    return Response(generate_frames(frame_queue), mimetype='multipart/x-mixed-replace; boundary=frame')


@app.route('/stop_stream')
def stop_stream():
    with lock:
        streaming_video.value = False
    return """
    <html>
        <head>
            <style>
                body {
                    margin: 0;
                    background-color: black;
                    height: 100vh;
                }
            </style>
        </head>
        <body>
        </body>
    </html>
    """, 200


def genHeader(sampleRate, bitsPerSample, channels):
    datasize = 2000 * 10 ** 6
    o = bytes("RIFF", 'ascii')  # (4byte) Marks file as RIFF
    o += (datasize + 36).to_bytes(4, 'little')  # (4byte) File size in bytes excluding this and RIFF marker
    o += bytes("WAVE", 'ascii')  # (4byte) File type
    o += bytes("fmt ", 'ascii')  # (4byte) Format Chunk Marker
    o += (16).to_bytes(4, 'little')  # (4byte) Length of above format data
    o += (1).to_bytes(2, 'little')  # (2byte) Format type (1 - PCM)
    o += (channels).to_bytes(2, 'little')  # (2byte)
    o += (sampleRate).to_bytes(4, 'little')  # (4byte)
    o += (sampleRate * channels * bitsPerSample // 8).to_bytes(4, 'little')  # (4byte)
    o += (channels * bitsPerSample // 8).to_bytes(2, 'little')  # (2byte)
    o += (bitsPerSample).to_bytes(2, 'little')  # (2byte)
    o += bytes("data", 'ascii')  # (4byte) Data Chunk Marker
    o += (datasize).to_bytes(4, 'little')  # (4byte) Data size in bytes
    return o


is_streaming = True

@app.route('/stop_audio')
def stop_audio():
    global is_streaming
    is_streaming = False
    return "Audio streaming stopped"

@app.route('/audio')
def audio():
    global is_streaming
    is_streaming = True  # 스트리밍 시작 시 항상 True로 초기화

    def sound():
        CHUNK = 1024
        sampleRate = 44100
        bitsPerSample = 16
        channels = 2
        wav_header = genHeader(sampleRate, bitsPerSample, channels)

        stream = audio1.open(format=FORMAT, channels=CHANNELS,
                             rate=RATE, input=True, input_device_index=1,
                             frames_per_buffer=CHUNK)
        print("recording...")
        first_run = True
        while is_streaming:
            if first_run:
                data = wav_header + stream.read(CHUNK)
                first_run = False
            else:
                data = stream.read(CHUNK)
            yield data

        stream.stop_stream()
        stream.close()

    return Response(sound())

@app.route('/upload', methods=['POST'])
def upload_audio():
    global file_path

    if 'file' not in request.files:
        print("No file part")
        return "No file part", 400

    file = request.files['file']
    if file.filename == '':
        print("No selected file")
        return "No selected file", 400

    path = os.path.join(file_path, file.filename)

    print(path)
    file.save(path)

    # 새로운 스레드에서 파일 재생
    threading.Thread(target=play_audio, args=(path,)).start()

    return f"File saved at {path}", 200

def play_audio(file_path):
    try:
        print("파일 재생 중...")
        pygame.mixer.init()  # 오디오 초기화
        pygame.mixer.music.load(file_path)
        pygame.mixer.music.play()

        # 음악이 재생되는 동안 대기
        while pygame.mixer.music.get_busy():
            continue

        print("파일 재생 완료")
    except Exception as e:
        print(f"오디오 파일 재생 실패: {e}")
    finally:
        pygame.mixer.music.unload()
        pygame.mixer.quit()

@app.route('/trigger')
def trigger_event():
    try:
        # 소켓 연결 생성
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((SOCKET_HOST, SOCKET_PORT))
            # 메시지 전송
            s.sendall(b"Triggered")
        return "Event triggered and sent to C server!", 200
    except Exception as e:
        return f"Failed to connect to C server: {e}", 500

@app.route('/')
def Index():
    return render_template('index.html')  # index.html 렌더링


if __name__ == "__main__":
    try:
        app.run('0.0.0.0', port=5000, debug=True, threaded=True)
    finally:
        capture.release()  # 서버 종료 시 웹캠 리소스 해제
