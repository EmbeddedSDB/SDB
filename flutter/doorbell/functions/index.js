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
        title: "Visitor 컬렉션: 새 데이터 추가",
        body: `새 데이터: ${JSON.stringify(newData)}`,
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
        title: "bell 컬렉션: 새 데이터 추가",
        body: `새 데이터: ${JSON.stringify(newData)}`,
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