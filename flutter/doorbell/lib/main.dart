import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart'; // 임시 저장소 경로를 가져오기 위해 사용
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

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

  bool isRecordPressed = false;

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
        title: Text('스마트 도어벨'),
        actions: [
          IconButton(
            icon: Icon(Icons.list),
            onPressed: () {
              // 오른쪽 위 버튼 클릭 시 비디오 리스트 화면으로 이동
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => VideoListScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // IP 입력 및 저장
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'IP 주소 입력',
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveIp,
                  child: Text('IP 저장'),
                ),
              ],
            ),
            SizedBox(height: 16),
            // 카메라와 소리 듣기 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _toggleWebcam,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _showWebcam ? Colors.blue : Colors.white,
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(20),
                  ),
                  child: Icon(
                    Icons.videocam,
                    color: _showWebcam ? Colors.white : Colors.blue,
                    size: 30,
                  ),
                ),
                ElevatedButton(
                  onPressed: _isPlaying ? _stopStreaming : _startStreaming,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPlaying ? Colors.blue : Colors.white,
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(20),
                  ),
                  child: Icon(
                    Icons.volume_up,
                    color: _isPlaying ? Colors.white : Colors.blue,
                    size: 30,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            // 카메라 화면
            Container(
              height: 265,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black),
              ),
              child: _showWebcam
                  ? WebViewWidget(controller: _webViewController)
                  : Container(color: Colors.black), // 검은색으로 채우기
            ),
            SizedBox(height: 16),
            // 녹음 버튼과 문 열기 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onLongPressStart: (details) {
                    setState(() {
                      isRecordPressed = true;
                    });
                    startRecording();
                  },
                  onLongPressEnd: (details) async {
                    setState(() {
                      isRecordPressed = false;
                    });
                    await stopRecording();
                    await uploadAudio();
                  },
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecordPressed ? Colors.blue : Colors.white,
                      shape: CircleBorder(),
                      padding: const EdgeInsets.all(20),
                    ),
                    child: Icon(
                      Icons.mic,
                      color: isRecordPressed ? Colors.white : Colors.blue,
                      size: 30,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _sendRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: CircleBorder(),
                    padding: const EdgeInsets.all(20),
                  ),
                  child: const Icon(
                    Icons.door_front_door_rounded,
                    color: Colors.blue,
                    size: 30,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class VideoListScreen extends StatefulWidget {
  @override
  _VideoListScreenState createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  List<Map<String, dynamic>> videoData = [];
  bool isLoading = true; // 로딩 상태

  @override
  void initState() {
    super.initState();
    _fetchVideoList();
  }

  // Firebase Storage에서 비디오 리스트 가져오기
  Future<void> _fetchVideoList() async {
    try {
      final ref = FirebaseStorage.instance.ref('videos'); // 'videos' 디렉토리 참조
      final result = await ref.listAll(); // 모든 파일 가져오기

      // 각 파일의 메타데이터 및 URL 가져오기
      final videoInfo = await Future.wait(
        result.items.map((fileRef) async {
          final metadata = await fileRef.getMetadata(); // 파일 메타데이터 가져오기
          final url = await fileRef.getDownloadURL(); // 파일 다운로드 URL 가져오기

          // 저장 시점을 읽고 형식화
          final createdTime = metadata.timeCreated ?? DateTime.now();
          final formattedTime = '${createdTime.year}-${createdTime.month.toString().padLeft(2, '0')}-${createdTime.day.toString().padLeft(2, '0')} ${createdTime.hour.toString().padLeft(2, '0')}:${createdTime.minute.toString().padLeft(2, '0')}';

          return {
            'url': url,
            'name': formattedTime, // 저장된 시점으로 이름 설정
          };
        }).toList(),
      );

      setState(() {
        videoData = videoInfo; // 비디오 데이터 저장
        isLoading = false; // 로딩 완료
      });
    } catch (e) {
      print('Error fetching video list: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('녹화 목록'),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator()) // 로딩 중
          : videoData.isEmpty
          ? Center(child: Text('비디오가 없습니다.')) // 비디오가 없을 때
          : ListView.builder(
        itemCount: videoData.length,
        itemBuilder: (context, index) {
          final video = videoData[index];
          return ListTile(
            title: Text(video['name']), // 저장 시점 표시
            onTap: () {
              // 특정 비디오 선택 시 재생 화면으로 이동
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      VideoPlayerScreen(videoUrl: video['url']),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerScreen({required this.videoUrl});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {}); // 초기화 완료 후 화면 갱신
        _controller.play();
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Play Video'),
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        )
            : CircularProgressIndicator(), // 로딩 중
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
