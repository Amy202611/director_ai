import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace")
lines = [line for line in text.splitlines() if re.search(r"\berror:|fatal error:|ARCHIVE FAILED", line, re.I)]
if re.search(r"\.swift:\d+.*error:|cannot find|cannot convert", text, re.I):
    kind = "Swift 源码编译错误"
elif re.search(r"database is locked|connection reset|timed out|failed to fetch", text, re.I):
    kind = "临时构建/网络错误：允许清理后重试一次"
else:
    kind = "构建配置错误：查看完整日志"
print("# 构建错误分析\n\n" + kind + "\n\n~~~text\n" + "\n".join(lines[:50]) + "\n~~~")
