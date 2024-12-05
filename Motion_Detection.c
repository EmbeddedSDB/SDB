#include <stdio.h>
#include <stdlib.h>
#include <wiringPi.h>
#include <pthread.h>
#include <unistd.h> // usleep() 마이크로 단위 sleep
#include <string.h>

#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>

#include <fcntl.h>

// 임시 파일
#define STATUS_FILE "/home/pi/SDB/tmp/record_status_signal.txt"

// 핀
#define PIR_PIN 24      // GPIO 24 모션감지 센서
#define BUTTON_PIN 23   // GPIO 23 초인종
// #define SERVO_PIN 19    // GPIO 19 서브모터 다른 코드에서 사용 중임...
#define BUZZER_PIN 17 // GPIO 17 부저

// 서브모터 설정
#define MIN_PULSE_WIDTH 50  // 최소 펄스
#define MAX_PULSE_WIDTH 250 // 최대 펄스
#define PWM_RANGE 2000      // pwm range
#define PWM_CLOCK_DIVISOR 192 // Clock

pid_t python_pid = -1; //python 프로세스 PID 저장

// 공유 변수
volatile int doorbellState = 0;         // 초인종 버튼이 눌러지면
volatile int personRecognition = 0;    // 사람이 감지되면
volatile int servoActionFlag = 0;      // 서브모터 flag -> 다 돌때까지 감지 해야 할 듯?

// firebase 알람 트리거
void uploadToFirebase() {
    int result = system("/home/pi/SDB/myenv/bin/python3 /home/pi/SDB/firebaseUpload.py");
    if (result == 0) {
        printf("Firebase 업로드 성공\n");
    } else {
        printf("Firebase 실패");
    }
}


///////////////////////////////////////////////////////////// C to python
// Python 스크립트 실행
void recordProcess() {
    if(python_pid == -1) {

        unlink(STATUS_FILE);

        pid_t pid = fork();
        if (pid < 0) {
            perror("fork 실패");
            return;
        } else if (pid == 0) {
            // 자식 프로세스: Python 스크립트 실행
            execlp("/home/pi/SDB/myenv/bin/python3", "python3", "/home/pi/SDB/recordStatus.py", NULL);
            perror("Python 실행 실패");
            exit(EXIT_FAILURE);
        }
        python_pid = pid;
        printf("Python 스크립트 실행됨, PID: %d\n", pid);
    } else {
        printf("Python 스크립트 이미 실행 중...\n");
    }
}

// 상태 파일에 신호 쓰기
void writeSignalToFile(const char *signal) {
    FILE *file = fopen(STATUS_FILE, "w");
    if (file == NULL) {
        perror("파일 열기 실패");
        return;
    }
    fprintf(file, "%s", signal);
    fclose(file);
    printf("신호 파일에 기록: %s\n", signal);
}

// Python 프로세스 종료 요청
void stopPythonScript() {
    if (python_pid != -1) {
        writeSignalToFile("0");  // 종료 신호 파일에 기록
        printf("Python 스크립트 종료 요청됨, PID: %d\n", python_pid);
        python_pid = -1;  // PID 리셋
    } else {
        printf("Python 스크립트가 실행 중이 아님\n");
    }
}

///////////////////////////////////////////////////////////// 여기까지 C to python

// 펄스 값 angle로 변경
int angleToPulseWidth(float angle) {
    return (int)((angle + 90) * (MAX_PULSE_WIDTH - MIN_PULSE_WIDTH) / 180 + MIN_PULSE_WIDTH);
}

// 모션 감지 스레드
void *motionDetectionThread(void *arg) {
    int personDetected = 0; // 사람을 감지하면?

    while (1) {
        int motionDetected = digitalRead(PIR_PIN);

        if (motionDetected && !personDetected) {
            //사람 감지 하고 녹화 프로그램 시작
            personRecognition = 1;
            personDetected = 1;
            // printf("사람 감지, 녹화 프로그램 시작\n");
            recordProcess();
        } else if (!motionDetected && personDetected) {
            // 3초 동안 기다림
            delay(3000);
            if (!digitalRead(PIR_PIN)) {
                personRecognition = 0;
                personDetected = 0;
                // printf("사람 없음, 녹화 프로그램 종료\n");
                stopPythonScript();
            }
        }
        delay(500);
    }
    return NULL;
}

// 초인종 스레드
void *buttonPressThread(void *arg) {
    // 버튼이 꾹 눌러질 때 처리
    int buttonState = HIGH; // 버튼 초기 상태 
    int lastButtonState = HIGH; // 버튼 나중 상태
    while (1) {
        buttonState = digitalRead(BUTTON_PIN);

        // 버튼 감지
        if (buttonState == LOW && lastButtonState == HIGH) {
            doorbellState = 1; // Doorbell was pressed
            printf("초인종이 눌러짐, 알람 전송\n");

            uploadToFirebase();

            printf("화상통화 프로세스 시작\n");
        }

        // 버튼 상태 업데이트
        lastButtonState = buttonState;

        delay(50); // 디바운싱 처리 (짧게..?)
    }
    return NULL;
}

void playTone(int frequency, int duration) {
    int period = 1000000 / frequency;
    int halfPeriod = period / 2;

    for (int i = 0; i < (duration * 1000) / period; i++) {
        digitalWrite(BUZZER_PIN, HIGH);
        usleep(halfPeriod);
        digitalWrite(BUZZER_PIN, LOW);
        usleep(halfPeriod);
    }
}

void *buzzerThread(void *arg) {
    while (1) {
        if (doorbellState) {
            printf("Buzzer: Ding-dong\n");

            playTone(523, 400);
            usleep(100000);
            playTone(392, 400);

            digitalWrite(BUZZER_PIN, LOW);

            doorbellState = 0;
        }
        usleep(100000);
    }
    return NULL;
}


int main() {

    if (wiringPiSetupGpio() == -1) {
        printf("Failed to initialize WiringPi with GPIO mode!\n");
        return 1;
    }

    pinMode(PIR_PIN, INPUT); 
    pinMode(BUTTON_PIN, INPUT);
    pinMode(BUZZER_PIN, OUTPUT);
    digitalWrite(BUZZER_PIN, LOW);
    pullUpDnControl(BUTTON_PIN, PUD_UP);

    unlink(STATUS_FILE);

    // 서보 모터 프로세스 코드 시작
    pid_t pid = fork();

    if(pid < 0) {
        perror("fork 실패");
        exit(EXIT_FAILURE);
    } else if (pid == 0){
        printf("서보모터 프로세스 실행");
        execlp("./motor", "./motor", NULL);
        perror("execlp 실패");
        exit(EXIT_FAILURE);
    } else {
        pthread_t motionThread, buttonThread, buzzerThreadId;

        if (pthread_create(&motionThread, NULL, motionDetectionThread, NULL) != 0) {
            printf("모션 스레드 생성 실패\n");
            return 1;
        }

        if (pthread_create(&buttonThread, NULL, buttonPressThread, NULL) != 0) {
            printf("버튼 스레드 생성 실패\n");
            return 1;
        }

        if (pthread_create(&buzzerThreadId, NULL, buzzerThread, NULL) != 0) {
            printf("버저 스레드 생성 실패\n");
            return 1;
        }

        // 메인 스레드
        while (1) {
            if (personRecognition) {
                printf("사람 감지 O\n");
            } else {
                printf("사람 감지 X\n");
            }
            delay(1000);
        }

        // 스레드
        pthread_join(motionThread, NULL);
        pthread_join(buttonThread, NULL);
        pthread_join(buzzerThreadId, NULL);

        wait(NULL);
        printf("자식 프로세스 종료됨");
    }

    return 0;
}
