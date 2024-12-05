import socket
from flask import Flask

app = Flask(__name__)

# 서버의 소켓 설정
SOCKET_HOST = '127.0.0.1'  # 로컬호스트
SOCKET_PORT = 65432        # C 서버가 대기 중인 포트

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

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')

