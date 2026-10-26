"""website_dsh 本地静态预览服务器。

支持 HTTP 字节范围请求，保证 <video> 的拖拽定位与放大窗口续播正常。
只监听本机回环地址。用法：

    python3 website_dsh/scripts/preview.py [--port 4174]

访问 http://127.0.0.1:4174 ，按 Ctrl+C 停止。
"""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from functools import partial
import argparse, os, re


class RangeHandler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def send_head(self):
        self.byte_range = None
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().send_head()
        try:
            stream = open(path, "rb")
        except OSError:
            self.send_error(404)
            return None
        size = os.fstat(stream.fileno()).st_size
        start, end = 0, size - 1
        header = self.headers.get("Range")
        if header:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", header.strip())
            valid = bool(match and any(match.groups()))
            if valid:
                first, last = match.groups()
                if first:
                    start = int(first)
                    end = min(size - 1, int(last)) if last else size - 1
                else:
                    length = int(last)
                    start = max(0, size - length)
                    valid = length > 0
                valid = valid and 0 <= start <= end < size
            if not valid:
                stream.close()
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return None
            self.byte_range = (start, end)
        self.send_response(206 if self.byte_range else 200)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(end - start + 1))
        if self.byte_range:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        stream.seek(start)
        return stream

    def copyfile(self, source, outputfile):
        if not self.byte_range:
            return super().copyfile(source, outputfile)
        left = self.byte_range[1] - self.byte_range[0] + 1
        while left:
            block = source.read(min(left, 1024 * 1024))
            if not block:
                break
            outputfile.write(block)
            left -= len(block)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4174)
    args = parser.parse_args()
    directory = Path(__file__).resolve().parents[1]
    server = ThreadingHTTPServer(
        ("127.0.0.1", args.port), partial(RangeHandler, directory=str(directory))
    )
    print(f"一读 · One Read website_dsh preview: http://127.0.0.1:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
