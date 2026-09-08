"""从已选定的笑脸课表原稿同步应用图标及启动页图片。"""
from pathlib import Path
from shutil import copyfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "design/branding/happy-schedule.png"


def main():
    for relative in ("assets/icon/icon.png", "assets/splash/logo.png"):
        destination = ROOT / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        copyfile(SOURCE, destination)
        print(f"OK: {relative}")


if __name__ == "__main__":
    main()
