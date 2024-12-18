from flask import Flask, render_template, Response, request
import time
import cv2
from multiprocessing import Process, Value, Lock, Queue
import threading
import pygame
import socket
import subprocess
import pyaudio
import os
import atexit
from picamera2 import Picamera2
import firebase_video_upload

app = Flask(__name__)

# 서버의 소켓 설정
SOCKET_HOST = '127.0.0.1'  # 로컬호스트
SOCKET_PORT = 65432        # C 서버가 대기 중인 포트

# 업로드 경로 설정
audio_path = "/home/pi/records"
os.makedirs(audio_path, exist_ok=True)

file_path = "/home/pi/control.txt"  #텍스트 파일 경로
streaming_path = "/home/pi/streaming.txt" #스트리밍 검사
video_dir = "/home/pi/videos"  #비디오를 저장할 디렉토리

# 비디오 저장 폴더 생성
os.makedirs(video_dir, exist_ok=True)

# 최대 업로드 크기 설정 (예: 50MB)
app.config['MAX_CONTENT_LENGTH'] = 10 * 1024 * 1024  # 50MB

FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 44100
RECORD_SECONDS = 5

audio1 = pyaudio.PyAudio()
capture = False
stream = None

frame_queue = Queue(maxsize=10)

lock = Lock()  # 스레드 안전성을 위해 Lock 객체 생성

# Picamera2 전역 인스턴스 생성
picam2 = None  # Picamera2 초기화 전역 변수
streaming_video = Value('b', False)  # 비디오 스트리밍 상태

def start_recording():
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    video_path = os.path.join(video_dir, f"{timestamp}.h264")

    print("영상 녹화를 시작합니다.")
    command = [
        "libcamera-vid",
        "-t", "0",
        "-o", video_path
    ]
    process = subprocess.Popen(command)
    return process, video_path

def convert_to_mp4(video_path):
    convert_command = [
        "ffmpeg",
        "-i", video_path,
        "-c:v", "copy",
        video_path.replace(".h264", ".mp4")
    ]
    print("MP4로 변환 중...")
    subprocess.run(convert_command)
    print(f"MP4 변환이 완료되었습니다: {video_path.replace('.h264', '.mp4')}")

def recording_controller():
    prev_state = None
    recording_process = None
    current_video_path = None
    global capture

    while True:
        if not streaming_video.value:
            try:
                # 텍스트 파일에서 상태 읽기
                with open(file_path, "r") as f:
                    state = f.read().strip()

                if state == "1" and prev_state != "1":
                    prev_state = state
                    # 녹화 시작
                    if recording_process is None:
                        capture = True
                        print("녹화가 시작되었습니다.")
                        time.sleep(2)
                        recording_process, current_video_path = start_recording()

                        for _ in range(100):  # 10초 동안 상태 확인 (0.1초 간격)
                            time.sleep(0.1)
                            with open(file_path, "r") as f:
                                updated_state = f.read().strip()
                            if updated_state == "0":
                                print("녹화를 취소합니다.")
                                recording_process.terminate()
                                recording_process.wait()
                                recording_process = None

                                if current_video_path:
                                    try:
                                        os.remove(current_video_path)
                                        print("짧은 녹화본 삭제")
                                    except Exception as e:
                                        print("파일 삭제 실패")
                                current_video_path = None
                                break
                        else:
                            print("10초 이상 인식되어 녹화를 유지합니다")
                    else:
                        print("이미 녹화 중입니다.")

                elif state == "0" and prev_state != "0":
                    prev_state = state
                    # 녹화 중지
                    if recording_process is not None:
                        print("영상 녹화를 중지합니다...")
                        recording_process.terminate()
                        recording_process.wait()
                        recording_process = None

                        if current_video_path:
                            convert_to_mp4(current_video_path)
                            firebase_video_upload.upload_file_to_firebase(current_video_path.replace('.h264', '.mp4'), "videos/" + time.strftime("%Y%m%d_%H%M%S") + ".mp4")
                            current_video_path = None
                        
                    else:
                        print("녹화 중이 아닙니다.")
                    release_camera()
                    capture = False

                
                #print('녹화 대기 중 ' + state)
                time.sleep(0.1)
            except FileNotFoundError:
                print(f"{file_path} 파일이 존재하지 않습니다. 대기 중...")
            except Exception as e:
                print(f"오류 발생: {e}")
        time.sleep(0.1)

def initialize_camera():
    """Picamera2 초기화 (한 번만 실행)"""
    global picam2, capture
    while(capture):
        print("")
    if picam2 is not None:
        return
    try:
        picam2 = Picamera2()
        camera_config = picam2.create_video_configuration(
            main={"size": (640, 480), "format": "RGB888"},
            controls={"NoiseReductionMode": 2, "AwbEnable": True}
        )
        picam2.configure(camera_config)
        picam2.start()
    except Exception as e:
        print(f"Error initializing camera: {e}")
        picam2 = None
def release_camera():
    """Picamera2 종료"""
    global picam2
    if picam2 is not None:
        print("Releasing camera resources...")
        try:
            picam2.stop()
            picam2.close()
            print("Camera stopped successfully.")
        except Exception as e:
            print(f"Error stopping camera: {e}")
        finally:
            picam2 = None
    else:
        print("Camera was already released.")

# 애플리케이션 종료 시 Picamera2 리소스 해제
atexit.register(release_camera)

def generate_frames():
    """Picamera2에서 프레임 생성"""
    global picam2
    initialize_camera()  # Picamera2 초기화
    while streaming_video.value:
        try:
            if picam2 is None:
                break
            frame = picam2.capture_array()
            _, buffer = cv2.imencode('.jpg', frame)
            frame = buffer.tobytes()
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
        except Exception as e:
            print(f"Error generating frame: {e}")
            break

@app.route('/stream')
def stream():
    """비디오 스트리밍 엔드포인트"""
    
    with lock:
        if not streaming_video.value:
            try:
                if picam2 is None:
                    initialize_camera()
                config = open(file_path, "w")
                streaming = open(streaming_path, 'w')
                config.write("0")
                streaming.write("0")
                
                time.sleep(3)
                while(capture):
                    print('waiting')
                    time.sleep(3)
                streaming_video.value = True
            except Exception as e:
                print("error")
                return "Failed to start ", 500
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')


@app.route('/stop_stream')
def stop_stream():
    with lock:
        streaming_video.value = False
        release_camera()
        streaming = open(streaming_path, 'w')
        streaming.write("1")
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


is_streaming = False

@app.route('/audio')
def audio():
    """오디오 스트리밍 시작 엔드포인트"""
    global is_streaming, stream
    if is_streaming:  # 이미 스트리밍 중인 경우
        print("Audio streaming is already running.")
        return "Audio streaming is already running.", 400

    is_streaming = True
    return Response(audio_stream(), mimetype="audio/wav")


@app.route('/stop_audio')
def stop_audio():
    """오디오 스트리밍 중지 엔드포인트"""
    global is_streaming, stream, audio1
    if not is_streaming:  # 스트리밍이 이미 중지된 경우
        print("No audio stream to stop.")
        return "No audio stream to stop.", 400

    is_streaming = False
    if stream:
        try:
            print("Stopping audio stream...")
            stream.stop_stream()
            stream.close()
            stream = None
        except Exception as e:
            print(f"Error stopping audio stream: {e}")
    if audio1:
        audio1.terminate()  # PyAudio 리소스 해제
        audio1 = pyaudio.PyAudio()  # 새 PyAudio 객체 초기화
    return "Audio streaming stopped.", 200


def audio_stream():
    """오디오 스트리밍 생성"""
    global stream, is_streaming, audio1
    CHUNK = 256
    sampleRate = 44100
    bitsPerSample = 16
    channels = 1

    try:
        wav_header = genHeader(sampleRate, bitsPerSample, channels)
        stream = audio1.open(
            format=FORMAT, channels=CHANNELS, input_device_index=2,
            rate=RATE, input=True, frames_per_buffer=CHUNK
        )
        print("Audio stream started.")
        first_run = True
        while is_streaming:
            if first_run:
                data = wav_header + stream.read(CHUNK, exception_on_overflow=False)
                first_run = False
            else:
                data = stream.read(CHUNK, exception_on_overflow=False)
            yield data
    except Exception as e:
        print(f"Audio streaming error: {e}")
    finally:
        if stream:
            stream.stop_stream()
            stream.close()
            stream = None
        print("Audio stream stopped.")



@app.route('/upload', methods=['POST'])
def upload_audio():
    global audio_path

    if 'file' not in request.files:
        print("No file part")
        return "No file part", 400

    file = request.files['file']
    if file.filename == '':
        print("No selected file")
        return "No selected file", 400

    path = os.path.join(audio_path, file.filename)

    print(path)
    file.save(path)

    # 새로운 스레드에서 파일 재생
    threading.Thread(target=play_audio, args=(path,)).start()

    return f"File saved at {path}", 200

def play_audio(audio_path):
    try:
        print("파일 재생 중...")
        pygame.mixer.init()  # 오디오 초기화
        pygame.mixer.music.load(audio_path)
        pygame.mixer.music.play()

        # 음악이 재생되는 동안 대기
        while pygame.mixer.music.get_busy():
            continue

        print("파일 재생 완료")
    except Exception as e:
        print(f"오디오 파일 재생 실패: {e}")
    finally:
        
        pygame.mixer.music.unload()
        pygame.mixer.music.stop()
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

@atexit.register
def cleanup_resources():
    global stream, audio1
    try:
        # 오디오 스트림 정리
        if stream:
            stream.stop_stream()
            stream.close()
            stream = None
            print("Cleaning up audio stream...")

        # PyAudio 정리
        if audio1:
            audio1.terminate()
            audio1 = None
            print("Terminating PyAudio...")

        print("Audio resources cleaned up successfully.")
    except Exception as e:
        print(f"Error during cleanup: {e}")


if __name__ == "__main__":
    try:
        print("안녕 ㅂ")
        recording_controller_process = Process(target=recording_controller)
        recording_controller_process.start()
        app.run('0.0.0.0', port=5000, debug=False, threaded=True)
        print("안녕 ㅅ")
    finally:
        release_camera()
