import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

late WebSocketChannel _channel;

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
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _recorder = FlutterSoundRecorder();
    _initializeRecorder();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  Future<void> _initializeRecorder() async {
    await _recorder!.openRecorder(); // 오디오 세션 열기
  }

  @override
  void dispose() {
    _recorder!.closeRecorder();
    _audioPlayer.dispose(); // 리소스 해제
    super.dispose();
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

  // Future<void> _startRecording() async {
  //   await _checkAndRequestPermissions(); // 권한 요청
  //
  //   final String audioUrl = "http://$_savedIp:5000/stream_to_speaker"; // 입력받은 IP 주소 사용
  //   _channel = WebSocketChannel.connect(
  //     Uri.parse(audioUrl),
  //   );
  //
  //   // 오디오 녹음 시작
  //   await _recorder?.openRecorder();
  //   await _recorder?.startRecorder(
  //     codec: Codec.pcm16, // PCM 포맷
  //     toStream: (StreamSink<Uint8List> sink) {
  //       return (dynamic buffer) {
  //         if (buffer is Uint8List) {
  //           // WebSocket으로 PCM 데이터 전송
  //           _channel.sink.add(buffer);
  //         }
  //       };
  //     },
  //   );
  //   print("Streaming started...");
  // }

  Future<void> stopStreaming() async {
    await _recorder?.stopRecorder();
    await _recorder?.closeRecorder();
    _channel.sink.close();
    print("Streaming stopped.");
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
            // ElevatedButton(
            //   onPressed: () {
            //     if (_isRecording) {
            //       _stopRecording();
            //     } else {
            //       _startRecording();
            //     }
            //   },
            //   child: Text(_isRecording ? "Stop Recording" : "Start Recording"),
            // ),
          ],
        ),
      ),
    );
  }
}