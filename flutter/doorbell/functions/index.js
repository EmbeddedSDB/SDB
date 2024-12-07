const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

// visitor 컬렉션 트리거
exports.notifyOnFirestoreCreateVisitor = onDocumentCreated(
  "visitor/{docId}",
  (event) => {
    const newData = event.data; // 새로 생성된 문서 데이터

    const message = {
      notification: {
        title: "문 앞에서 움직임이 감지되었어요!",
        body: "앱을 켜서 확인해보세요.",
      },
      topic: "visitor-updates", // visitor 주제로 푸시 알림 전송
    };

    return admin.messaging().send(message)
      .then((response) => {
        console.log("푸시 알림 전송 성공:", response);
      })
      .catch((error) => {
        console.error("푸시 알림 전송 실패:", error);
      });
  }
);

// bell 컬렉션 트리거
exports.notifyOnFirestoreCreatebell = onDocumentCreated(
  "bell/{docId}",
  (event) => {
    const newData = event.data; // 새로 생성된 문서 데이터

    const message = {
      notification: {
        title: "방문자가 있어요!",
        body: "앱을 켜서 확인해보세요.",
      },
      topic: "bell-updates", // bell 주제로 푸시 알림 전송
    };

    return admin.messaging().send(message)
      .then((response) => {
        console.log("푸시 알림 전송 성공:", response);
      })
      .catch((error) => {
        console.error("푸시 알림 전송 실패:", error);
      });
  }
);