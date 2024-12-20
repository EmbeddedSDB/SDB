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
  녹화 기능
</blockquote>
<br />
<p align="center">
  <img src="" alt="녹화 이미지" height="400">
</p>

사람이 초인종 앞에 있으면 동작 감지 센서에 의해서 감지 되고 이후 녹화 진행.  
사람이 앞에 없으면 녹화가 종료 혹은 일정 시간 만큼만 녹화.  
녹화된 영상은 파이어베이스를 통해서 전송되고 스마트폰 앱에서 확인 가능.
<br />

## 👨🏻‍💻 팀원 소개
| Profile | Role | Part |
| ------- | ---- | ---- |
| <div align="center"><a href="https://github.com/jsy0605" width="70px;" alt=""/><img src="https://github.com/user-attachments/assets/bae4b917-3c74-4fa2-ab8b-9efce2116c37" width="70px;" alt="dsky"/><br/><sub><b>정성윤</b><sub></a></div> | 팀장 | - 프로젝트 리더<br/>- 프로세스 일정 및 전반적인 관리<br/>- 라즈베리파이 통화 프로세스 구축<br/>- 카메라 연결 및 하드웨어 연결 <br/>- 화상 프로세스 구축|
| <div align="center"><a href="https://github.com/dsky03" width="70px;" alt=""/><img src="https://github.com/user-attachments/assets/610dfb5e-859b-4707-9638-6e36ae592a98" width="70px;" alt="jsy"/><br/><sub><b>김동천</b></sub></a></div> | 팀원 | - 메인 스레드 구축<br/>- 프로세스 연결 담당<br/>- 초인종, 동작 감지 센서 등 하드웨어 시스템 관리 |
| <div align="center"><a href="https://github.com/son0307"><img src="https://github.com/user-attachments/assets/59705e16-65fd-4f8b-918a-c5bc10f71676" width="70px;" alt="son"/><br/><sub><b>손민우</b></sub></a></div> | 팀원 | - 데이터 송수신 관리<br/>- 파이어베스 서버 구축 및 소켓 연결 <br/>- 스마트폰 통화 프로세스 구축<br/>- 화상 프로세스 구축| 
| <div align="center"><a href="https://github.com/choongmoo"><img src="https://github.com/user-attachments/assets/cf6248cb-967a-480e-b5f6-5c89f8b9434b" width="70px;" alt="choongmoo"/><br/><sub><b>허충무</b></sub></a></div> | 팀원 | - 녹화 시스템 개발<br/>- 녹화 파일 저장 및 전송 시스템 구축|

## 🛠️ 기술 스택
