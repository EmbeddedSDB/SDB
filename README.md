# 🔔 SDB (스마트 도어벨)
## 📖 프로젝트 소개
**SDB**는 기존의 도어벨에서 사용자의 편리를 한층 더 높인 스마트 도어벨.

사용자 편의성 제공
- 원격으로 방문자를 확인할 수 있다.
- 스마트폰을 이용해서 초인종 앞의 사람과 통화 가능.
- 방문자 확인 후 원격 도어락 제어.

안전한 집 환경 구축
- 문 앞 움직임을 감지하면 영상 녹화 후 스마트폰으로 확인 가능.
- 스마트폰을 이용해서 수동으로 직접 화상 프로세스를 실행 할 수도 있다.

## 📁 전체 구조


## ⌨ 구현 내용


## 🖥 주요 기능

<blockquote>
  동작 감지 센서 & 녹화 기능
</blockquote>
<br />
<p align="center">
  <img src="" alt="동작 감지 센서 이미지" height="400">
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="" alt="녹화 이미지" height="400">
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="" alt="스마트폰 알림1" height="400">
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="" alt="스마트폰 녹화" height="400">
</p>

- 사람이 문 앞에 있으면 동작 감지 센서에 의해서 감지 되고 이후 녹화 진행.
- 동작 감지 센서가 작동되면 스마트폰으로 문 앞에 누가 있다고 알림을 전송.  
- 사람이 앞에 없으면 녹화가 종료 혹은 일정 시간 만큼만 녹화.  
- 녹화된 영상은 파이어베이스를 통해서 전송되고 스마트폰 앱에서 확인 가능.
<br />

<blockquote>
  초인종 기능
</blockquote>
<br />
<p align="center">
  <img src="" alt="부저 이미지" height="400">
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="" alt="초인종 이미지" height="400">
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="" alt="스마트폰 알림2" height="400">
</p>

- 사람이 초인종을 누르면 부저를 통해 "딩동" 소리가 남.  
- 초인종을 누르면 스마트폰으로 누가 초인종을 눌렀다고 알림을 전송 .  
<br />

<blockquote>
  통화 기능
</blockquote>
<br />
<p align="center">
  <img src="" alt="라즈베리파이 스피커 & 마이크" height="400">
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="" alt="스마트폰 통화 기능" height="400">
</p>

- 스마트폰에서 마이크 버튼을 누르면 상대방에게 말할 수 있음.  
- 상대방에 초인종 앞에 부착된 마이크를 통해서 상대방에게 말 할 수 있음.  
- 스마트폰 자체 스피커를 통해 상대방의 말을 들을 수 있음.  
- 라즈베리파이에 연결된 스피커를 통해 상대방의 말을 들을 수 있음.  
- 파이어베이스를 통해서 음성 데이터를 전송함.
<br />

<blockquote>
  화상 프로세스
</blockquote>
<br />
<p align="center">
  <img src="" alt="스마트폰 화상 통화" height="400">
</p>

- 라즈베리파이의 카메라를 통해서 초인종 밖의 상황을 볼 수 있다.  
- 실시간 영상이 서버를 통해서 스마트폰으로 전송이 됨.
<br />

## 👨🏻‍💻 팀원 소개
| Profile | Role | Part |
| ------- | ---- | ---- |
| <div align="center"><a href="https://github.com/jsy0605" width="70px;" alt=""/><img src="https://github.com/user-attachments/assets/bae4b917-3c74-4fa2-ab8b-9efce2116c37" width="70px;" alt="dsky"/><br/><sub><b>정성윤</b><sub></a></div> | 팀장 | - 프로젝트 리더<br/>- 프로세스 일정 및 전반적인 관리<br/>- 라즈베리파이 통화 프로세스 구축<br/>- 카메라 연결 및 하드웨어 연결 <br/>- 화상 프로세스 구축|
| <div align="center"><a href="https://github.com/dsky03" width="70px;" alt=""/><img src="https://github.com/user-attachments/assets/610dfb5e-859b-4707-9638-6e36ae592a98" width="70px;" alt="jsy"/><br/><sub><b>김동천</b></sub></a></div> | 팀원 | - 메인 스레드 구축<br/>- 프로세스 연결 담당<br/>- 초인종, 동작 감지 센서 등 하드웨어 시스템 관리 |
| <div align="center"><a href="https://github.com/son0307"><img src="https://github.com/user-attachments/assets/59705e16-65fd-4f8b-918a-c5bc10f71676" width="70px;" alt="son"/><br/><sub><b>손민우</b></sub></a></div> | 팀원 | - 데이터 송수신 관리<br/>- 파이어베스 서버 구축 및 소켓 연결 <br/>- 스마트폰 통화 프로세스 구축<br/>- 화상 프로세스 구축| 
| <div align="center"><a href="https://github.com/choongmoo"><img src="https://github.com/user-attachments/assets/cf6248cb-967a-480e-b5f6-5c89f8b9434b" width="70px;" alt="choongmoo"/><br/><sub><b>허충무</b></sub></a></div> | 팀원 | - 녹화 시스템 개발<br/>- 녹화 파일 저장 및 전송 시스템 구축|

## 🛠️ 기술 스택
