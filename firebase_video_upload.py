import sys
import os

venv_path = "/home/pi/.local/lib/python3.11/site-packages"
sys.path.append(venv_path)

from firebase_admin import credentials, initialize_app, storage
# Firebase 설정
FIREBASE_STORAGE_BUCKET = "doorbell-66384.firebasestorage.app"

cred = credentials.Certificate('/home/pi/SDB/doorbell-66384-firebase-adminsdk-zjep1-548c6a3e22.json')
initialize_app(cred, {'storageBucket': FIREBASE_STORAGE_BUCKET})
bucket = storage.bucket()

def upload_file_to_firebase(local_path, firebase_path):
    """Firebase Storage에 파일 업로드"""
    try:
        # Firebase Storage로 파일 업로드
        blob = bucket.blob(firebase_path)
        blob.upload_from_filename(local_path)
        blob.make_public()  # 파일 공개 URL 생성 (선택)

        print(f"파일 업로드 완료: {local_path}")
        print(f"공개 URL: {blob.public_url}")
    except Exception as e:
        print(f"파일 업로드 실패: {e}")
