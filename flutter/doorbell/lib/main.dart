import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart'; // 임시 저장소 경로를 가져오기 위해 사용
import 'package:record/record.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options : DefaultFirebaseOptions.currentPlatform
  );

  await setupFirebaseMessaging();
  runApp(const MyApp());
}

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase 초기화
  await Firebase.initializeApp();

  // 알림 표시
  if (message.notification != null) {
    showNotification(
      message.notification!.title ?? "백그라운드 알림",
      message.notification!.body ?? "내용 없음",
    );
  }
}

Future<void> setupFirebaseMessaging() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // 주제 구독 (예: "updates")
  await messaging.subscribeToTopic("visitor-updates");
  await messaging.subscribeToTopic("bell-updates");

  // 알림 권한 요청
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  print('알림 권한: ${settings.authorizationStatus}');

  // 포그라운드 알림 처리
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.notification != null) {
      showNotification(
        message.notification!.title ?? "알림",
        message.notification!.body ?? "내용 없음",
      );
    }
  });

  // 백그라운드 및 종료 상태 알림 처리
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

}

// 전역 변수로 플러그인 선언
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// 채널을 전역적으로 정의
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel', // id
  'High Importance Notifications', // title
  description: 'This channel is used for important notifications.',
  importance: Importance.max,
);

Future<void> setupNotificationPlugin() async {
  // 플러그인 초기화
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // 채널 생성
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

void showNotification(String title, String body, {String? topic}) {
  String notificationTitle = title;
  String notificationBody = body;

  // 주제에 따라 알림 제목 및 본문 변경
  if (topic == "visitor-updates") {
    notificationTitle = "문 앞에서 움직임이 감지되었어요!";
    notificationBody = "앱을 켜서 확인해보세요.";
  } else if (topic == "orders-updates") {
    notificationTitle = "방문자가 있습니다!";
    notificationBody = "앱을 켜서 확인해보세요.";
  }

  // 알림 표시
  int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
  flutterLocalNotificationsPlugin.show(
    notificationId, // 알림 ID
    notificationTitle,
    notificationBody,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
      ),
    ),
  );
}


Future<void> _checkAndRequestPermissions() async {
  if (await Permission.microphone.isGranted) {
    print("Microphone permission granted.");
  } else {
    // 권한 요청
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      print("Microphone permission granted after request.");
    } else if (status.isDenied) {
      print("Microphone permission denied.");
    } else if (status.isPermanentlyDenied) {
      print("Microphone permission permanently denied. Please enable it in settings.");
      openAppSettings(); // 설정 화면으로 이동
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: IpInputScreen(),
    );
  }
}

class IpInputScreen extends StatefulWidget {
  @override
  _IpInputScreenState createState() => _IpInputScreenState();
}

class _IpInputScreenState extends State<IpInputScreen> {
  final TextEditingController _ipController = TextEditingController();
  String _savedIp = "";
  bool _showWebcam = false;
  late final WebViewController _webViewController;
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  final AudioRecorder _record = AudioRecorder();
  String? _recordedFilePath;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  Future<void> _stopStreaming() async {
    await _audioPlayer.stop(); // 스트리밍 중단
    final String audioStopUrl = "http://$_savedIp:5000/stop_audio";
    try {
      final response = await http.get(Uri.parse(audioStopUrl));
      print("서버 응답: ${response.statusCode}");
    } catch (e) {
      print("Error stopping audio stream: $e");
    }
    setState(() {
      _isPlaying = false;
    });
  }

  Future<void> _startStreaming() async {
    if (_savedIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("먼저 IP 주소를 저장해주세요.")),
      );
      return;
    }

    final String audioUrl = "http://$_savedIp:5000/audio"; // 입력받은 IP 주소 사용
    try {
      await _audioPlayer.stop(); // 이전 스트림 정리
      await _audioPlayer.setUrl(audioUrl); // 새로운 스트림 URL 설정
      _audioPlayer.play(); // 오디오 스트림 재생
      setState(() {
        _isPlaying = true;
      });
    } catch (e) {
      print("Error starting audio stream: $e");
    }
  }

  // 녹음 시작 함수
  Future<void> startRecording() async {
    if (await _record.hasPermission()) {
      // 앱의 임시 디렉토리에서 파일 저장 경로 가져오기
      Directory tempDir = await getTemporaryDirectory();
      String filePath = '${tempDir.path}/audio_recording.wav';

      // 녹음 시작
      await _record.start(
        path: filePath,
        const RecordConfig(),  // RecordConfig를 컨트롤 누르고 들어가서 this.encoder를 AudioEncoder.wav로 바꿔줘야 제대로 작동함.
      );

      print('녹음 시작: $filePath');
    } else {
      print('녹음 권한이 없습니다.');
    }
  }

  // 녹음 중지 함수
  Future<void> stopRecording() async {
    String? path = await _record.stop();

    if (path != null) {
      setState(() {
        _recordedFilePath = path;
      });
      print('녹음 완료: $path');
    }
  }

  // 업로드 함수
  Future<void> uploadAudio() async {
    if (_recordedFilePath == null) {
      print('녹음된 파일이 없습니다.');
      return;
    }

    File audioFile = File(_recordedFilePath!);
    var uri = Uri.parse('http://$_savedIp:5000/upload');
    var request = http.MultipartRequest('POST', uri);

    request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));
    var response = await request.send();

    if (response.statusCode == 200) {
      print('업로드 성공');
    } else {
      print('업로드 실패: ${response.statusCode}');
    }
  }

  // IP 저장
  void _saveIp() {
    setState(() {
      _savedIp = _ipController.text;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("IP 주소가 저장되었습니다: $_savedIp")),
    );
  }

  // 웹캠 보기 함수
  void _toggleWebcam() {
    if (_savedIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("먼저 IP 주소를 저장해주세요.")),
      );
      return;
    }

    setState(() {
      if(!_showWebcam) {
        _showWebcam = true; // 웹캠 표시
        _webViewController.loadRequest(
            Uri.parse('http://$_savedIp:5000/stream'));
      }
      else {
        _showWebcam = false;
        _webViewController.loadRequest(
            Uri.parse('http://$_savedIp:5000/stop_stream'));
      }
    });
  }

  // HTTP 요청
  Future<void> _sendRequest() async {
    if (_savedIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("먼저 IP 주소를 저장해주세요.")),
      );
      return;
    }
    final url = Uri.parse("http://$_savedIp:5000/trigger");

    try {
      final response = await http.get(url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("요청이 성공적으로 전송되었습니다.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("요청 실패: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('IP 입력 테스트'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'IP 주소 입력',
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saveIp,
              child: Text('IP 저장'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _sendRequest,
              child: Text('요청 전송'),
            ),
            SizedBox(height: 16),
            // 웹캠 보기 버튼
            ElevatedButton(
              onPressed: _toggleWebcam,
              child: Text('카메라 토글'),
            ),
            if (_showWebcam && _savedIp.isNotEmpty)
              Container(
                height: 265,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black),
                ),
                child: WebViewWidget(controller: _webViewController
                ),
              ),
            _isPlaying
                ? ElevatedButton(
                  onPressed: _stopStreaming,
                  child: Text('중단'),
            )
                : ElevatedButton(
                  onPressed: _startStreaming,
                  child: Text('소리 듣기'),
            ),
            GestureDetector(
              onLongPressStart: (details) {
                // 버튼을 누를 때 녹음 시작
                startRecording();
              },
              onLongPressEnd: (details) async {
                // 녹음 중지
                await stopRecording();

                // 녹음 중지가 완료된 후 파일 업로드
                await uploadAudio();
              },
              child: ElevatedButton(
                onPressed: () {}, // 활성화된 버튼 유지 (GestureDetector에서 이벤트 처리)
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, // 버튼 배경색 설정
                  shape: CircleBorder(), // 둥근 버튼
                  padding: const EdgeInsets.all(20), // 버튼 크기 설정
                ),
                child: const Icon(
                  Icons.mic, // 마이크 아이콘
                  color: Colors.white, // 아이콘 색상
                  size: 30, // 아이콘 크기
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
