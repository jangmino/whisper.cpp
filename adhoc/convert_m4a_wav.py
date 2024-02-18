import subprocess
import os


def convert_m4a_to_wav(folder_path):
    # 폴더 내의 모든 파일을 탐색
    for file in os.listdir(folder_path):
        if file.endswith(".m4a"):
            # 파일 이름에서 확장자 제거
            file_name_without_extension = os.path.splitext(file)[0]
            m4a_file_path = os.path.join(folder_path, file)
            wav_file_path = os.path.join(
                folder_path, f"{file_name_without_extension}.wav"
            )

            # ffmpeg 명령어 실행
            subprocess.run(
                [
                    "ffmpeg",
                    "-i",
                    m4a_file_path,
                    "-ar",
                    "16000",
                    "-ac",
                    "1",
                    "-c:a",
                    "pcm_s16le",
                    wav_file_path,
                ]
            )

    print("변환 완료!")


# 사용자에게 폴더 경로 입력 받기
folder_path = input("변환할 파일이 있는 폴더 경로를 입력하세요: ")
convert_m4a_to_wav(folder_path)
