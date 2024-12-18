import sys
import os

venv_path = "/home/pi/.local/lib/python3.11/site-packages"
sys.path.append(venv_path)

import firebase_admin
from firebase_admin import credentials, firestore

# Firebase Admin SDK 초기화
cred = credentials.Certificate('/home/pi/SDB/doorbell-66384-firebase-adminsdk-zjep1-548c6a3e22.json')
firebase_admin.initialize_app(cred)

# Firestore 클라이언트 초기화
db = firestore.client()

# 데이터 추가 함수
def add_data(collection_name, document_id, data):
    try:
        if document_id:
            # 문서 ID를 지정해 추가
            db.collection(collection_name).document(document_id).set(data)
        else:
            # 문서 ID를 자동으로 생성해 추가
            db.collection(collection_name).add(data)
        print("데이터가 성공적으로 추가되었습니다!")
    except Exception as e:
        print(f"데이터 추가 중 오류 발생: {e}")

# 데이터 예제
data = {
    "name": "John Doe",
    "email": "john.doe@example.com",
    "age": 30,
    "is_active": True
}

add_data("visitor", None, data)
