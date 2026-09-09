import pathlib
import re

# 常见乱码字符（UTF-8 被误读为 Latin-1 时产生的字符）
PATTERN = re.compile(
    r'[閸闁鍙鏉鐨鎴娴鏃鍚鎺璇鎵鏈鍣鍧顓勬簮'
    r'嬭瘯兼鍘涘弰缉闃囧瓨鏌婇鍫閿鐥張澶娣灟'
    r'劌錯樻閣嶇敤浠涓苟奼囨柤浜粯鍒犻櫎宸茬粡'
    r'挎帶惰繑鍥炶鏁版嵁瀵艰埅鏂囪寰栬鑺辩綉'
    r'鎺崲灞忓箷鍑嗗埌鏃堕棿闄愬埗鐧诲綍璐彿'
    r'灏佺绂鎷夐粦]'
)

# 忽略的目录名
IGNORE_DIRS = {'.git', '.dart_tool', 'build', '.idea', '.vscode', 'node_modules', '__pycache__'}
IGNORE_ROOT_DIRS = {'0.8.93', '2.0.7', '2.0.8', 'dist', 'v2_theme', 'apiez'}

# 需要扫描的文件后缀（白名单）
SCAN_EXTENSIONS = {'.dart', '.kt', '.java', '.cpp', '.h', '.hpp', '.yaml'}


def is_text_file(path: pathlib.Path) -> bool:
    """只扫描白名单中的后缀"""
    return path.suffix.lower() in SCAN_EXTENSIONS


def scan_file(path: pathlib.Path) -> list[tuple[int, str]]:
    """扫描单个文件，返回 [(行号, 行内容), ...]"""
    found: list[tuple[int, str]] = []
    try:
        with open(path, encoding='utf-8', errors='ignore') as f:
            for lineno, line in enumerate(f, 1):
                if PATTERN.search(line):
                    found.append((lineno, line.strip()))
    except Exception:
        pass
    return found


def main() -> None:
    self_name = pathlib.Path(__file__).name
    for file in pathlib.Path('.').rglob('*'):
        if file.is_dir():
            continue
        if any(part in IGNORE_DIRS for part in file.parts):
            continue
        if any(part in IGNORE_ROOT_DIRS for part in file.parts):
            continue
        if not is_text_file(file):
            continue
        if file.name == self_name:
            continue
        for lineno, line in scan_file(file):
            print(f'{file}:{lineno}')
            print(f'  {line[:120]}')


if __name__ == '__main__':
    main()