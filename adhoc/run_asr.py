import subprocess
import os


def process_wav_files(folder_path):
    # 폴더 내의 모든 파일을 탐색
    for file in os.listdir(folder_path):
        if file.endswith(".wav"):
            file_name_without_extension = os.path.splitext(file)[0]
            wav_file_path = os.path.join(folder_path, file)
            txt_file_path_without_extension = os.path.join(
                folder_path, f"{file_name_without_extension}"
            )

            # print(file_name_without_extension, wav_file_path, txt_file_path)

            # 주어진 명령 실행
            subprocess.run(
                [
                    "./main",
                    "-m",
                    # "models/ggml-medium.bin",
                    "models/ggml-medium-noisy.bin",
                    "-l",
                    "ko",
                    "-nt",
                    "-otxt",
                    "-of",
                    txt_file_path_without_extension,
                    "-f",
                    wav_file_path,
                ]
            )
            # break

    print("처리 완료!")


# 사용자에게 폴더 경로 입력 받기
folder_path = "/Users/jangmin/work/manna/speech_recgonition/real_data/wav"  # input("처리할 .wav 파일이 있는 폴더 경로를 입력하세요: ")
process_wav_files(folder_path)
