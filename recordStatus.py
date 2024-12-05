import os
import time

STATUS_FILE = "/home/pi/SDB/tmp/record_status_signal.txt"  # 신호 파일 경로

def recording():
    """
    녹화 코드가 아마 여기 들어갈 듯?
    """
    print("녹화 프로그램 실행 중.....")
    try:
        while True:
            if os.path.exists(STATUS_FILE):
                with open(STATUS_FILE, "r") as f:
                    signal = f.read().strip()
                if signal == "0":
                    print("종료 신호를 받음. 녹화 종료 로직...")
                    break
            print("녹화 중...")
            time.sleep(1)
    except KeyboardInterrupt:
        print("리코딩 에러")

def main():
    with open(STATUS_FILE, "w") as f:
        f.write("1")
    recording()

if __name__ == "__main__":
    main()
