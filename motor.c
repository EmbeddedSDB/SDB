#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <stdbool.h>

#include <wiringPi.h>
#include <softPwm.h>

#define PWM0 21
#define RANGE 2000

#define PORT 65432
#define BUFFER_SIZE 1024
#define QUEUE_SIZE 10

// 작업 큐
typedef struct {
    char *data[QUEUE_SIZE];
    int front;
    int rear;
    int count;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
} TaskQueue;

// 작업 큐 초기화
void init_queue(TaskQueue *queue) {
    queue->front = 0;
    queue->rear = 0;
    queue->count = 0;
    pthread_mutex_init(&queue->mutex, NULL);
    pthread_cond_init(&queue->cond, NULL);
}

// 작업 큐에 데이터 추가
void enqueue(TaskQueue *queue, const char *message) {
    pthread_mutex_lock(&queue->mutex);
    while (queue->count == QUEUE_SIZE) {
        // 큐가 가득 찬 경우 대기
        pthread_cond_wait(&queue->cond, &queue->mutex);
    }

    queue->data[queue->rear] = strdup(message); // 메시지 복사
    queue->rear = (queue->rear + 1) % QUEUE_SIZE;
    queue->count++;

    pthread_cond_signal(&queue->cond); // 대기 중인 소비자 알림
    pthread_mutex_unlock(&queue->mutex);
}

// 작업 큐에서 데이터 가져오기
char *dequeue(TaskQueue *queue) {
    pthread_mutex_lock(&queue->mutex);
    while (queue->count == 0) {
        // 큐가 비어 있는 경우 대기
        pthread_cond_wait(&queue->cond, &queue->mutex);
    }

    char *message = queue->data[queue->front];
    queue->front = (queue->front + 1) % QUEUE_SIZE;
    queue->count--;

    pthread_cond_signal(&queue->cond); // 대기 중인 생산자 알림
    pthread_mutex_unlock(&queue->mutex);

    return message;
}

int rotate_Servo(int angle)
{
    int duty = (float)(90 + angle) / 180 * 20; // softPwm은 0-100 범위에서 작동하므로 비율 조정
    softPwmWrite(PWM0, duty);
    delay(10);
    return 0;
}

// 글로벌 작업 큐
TaskQueue task_queue;

// 서보모터 제어 스레드
void *output_thread(void *arg) {
    while (true) {
        char *message = dequeue(&task_queue);
        
        rotate_Servo(0);
        delay(1000);
        rotate_Servo(90);
    }
    return NULL;
}

// 소켓 스레드
void *socket_thread(void *arg) {
    int server_fd = *(int *)arg;
    int client_socket;
    struct sockaddr_in address;
    int addrlen = sizeof(address);
    char buffer[BUFFER_SIZE];

    printf("Waiting for connections on port %d...\n", PORT);

    while (true) {
        // 클라이언트 연결 수락
        if ((client_socket = accept(server_fd, (struct sockaddr *)&address, 
                                    (socklen_t *)&addrlen)) < 0) {
            perror("Accept failed");
            continue;
        }

        // 메시지 읽기
        int valread = read(client_socket, buffer, BUFFER_SIZE);
        if (valread > 0) {
            buffer[valread] = '\0'; // 문자열 종료
            enqueue(&task_queue, buffer); // 작업 큐에 추가
        }

        close(client_socket); // 소켓 닫기
    }

    return NULL;
}

int main() {
    wiringPiSetupGpio();

    // 소프트 PWM 초기화
    if (softPwmCreate(PWM0, 0, 100) != 0) {
        fprintf(stderr, "SoftPwm setup failed\n");
        return 1;
    }

    rotate_Servo(90);

    pthread_t socket_tid, output_tid;

    // 작업 큐 초기화
    init_queue(&task_queue);

    // 소켓 서버 초기화
    int server_fd;
    struct sockaddr_in address;

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("Socket failed");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(PORT);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("Bind failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("Listen failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }

    // 소켓 스레드 생성
    if (pthread_create(&socket_tid, NULL, socket_thread, &server_fd) < 0) {
        perror("Socket thread creation failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }

    // 출력 스레드 생성
    if (pthread_create(&output_tid, NULL, output_thread, NULL) < 0) {
        perror("Output thread creation failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }

    // 메인 쓰레드는 다른 쓰레드 대기
    pthread_join(socket_tid, NULL);
    pthread_join(output_tid, NULL);

    close(server_fd);
    return 0;
}
