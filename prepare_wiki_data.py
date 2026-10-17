#!/usr/bin/env python3
"""
Download ~1 GiB of plain-text English Wikipedia and create smaller versions.

Output (in the "data" folder), each file being the first N bytes of the largest one:
    wiki_4KB.txt, wiki_16KB.txt, wiki_64KB.txt, wiki_256KB.txt, wiki_1MB.txt,
    wiki_4MB.txt, wiki_16MB.txt, wiki_64MB.txt, wiki_256MB.txt, wiki_1GB.txt

Sizes are powers of 1024 (KB = 1024 bytes, MB = 1024^2, GB = 1024^3) and are exact.

Usage (inside the virtual environment with `datasets` installed):
    python prepare_wiki_data.py

Re-running is safe: files that already exist with the correct size are skipped.
"""

import os
import sys
import time

from datasets import load_dataset

# ---------------------------------------------------------------- settings
OUT_DIR = "data"
DATASET = "wikimedia/wikipedia"
SNAPSHOT = "20231101.en"                          # English snapshot, Nov 1 2023
SIZES = [4 * 1024 * 4**i for i in range(10)]      # 4 KB, 16 KB, ... 1 GB (x4 each step)
FULL_SIZE = SIZES[-1]                             # 1 GB: the file that is downloaded
REPORT_EVERY = 50 * 1024**2                       # progress line every 50 MB
CHUNK = 16 * 1024**2                              # copy buffer for the smaller files


def label(n):
    """Human-readable size used in file names, e.g. 4096 -> '4KB'."""
    if n >= 1024**3:
        return f"{n // 1024**3}GB"
    if n >= 1024**2:
        return f"{n // 1024**2}MB"
    return f"{n // 1024}KB"


def file_path(size):
    return os.path.join(OUT_DIR, f"wiki_{label(size)}.txt")


def download(path, target):
    """Stream Wikipedia articles and write exactly `target` bytes of text to `path`."""
    if os.path.exists(path) and os.path.getsize(path) == target:
        print(f"{path} already exists, skipping download.")
        return

    print(f"Downloading {label(target)} of text from {DATASET} ({SNAPSHOT})...")
    print("(the first progress line can take a minute while the file list is fetched)")
    ds = load_dataset(DATASET, SNAPSHOT, split="train", streaming=True)

    tmp = path + ".part"            # renamed only when complete, so an interrupted
    written = 0                     # run never leaves a file that looks finished
    next_report = REPORT_EVERY
    start = time.time()

    with open(tmp, "wb") as f:
        for article in ds:
            data = (article["text"] + "\n\n").encode("utf-8")
            remaining = target - written
            if len(data) > remaining:
                data = data[:remaining]          # cut the last article to hit the exact size
            f.write(data)
            written += len(data)

            if written >= next_report or written >= target:
                elapsed = time.time() - start
                rate = written / elapsed / 1024**2
                eta = (target - written) / (rate * 1024**2) if rate > 0 else 0
                print(f"  {written / 1024**2:7.0f} MB / {target / 1024**2:.0f} MB"
                      f"  ({rate:5.1f} MB/s, about {eta / 60:4.1f} min left)", flush=True)
                next_report += REPORT_EVERY

            if written >= target:
                break

    if written < target:
        sys.exit(f"Error: the dataset ended after {written} bytes, less than requested.")

    os.replace(tmp, path)
    print(f"Download finished in {(time.time() - start) / 60:.1f} min.")


def make_prefix(src, dst, size):
    """Write the first `size` bytes of `src` into `dst`."""
    if os.path.exists(dst) and os.path.getsize(dst) == size:
        return
    with open(src, "rb") as fin, open(dst, "wb") as fout:
        remaining = size
        while remaining > 0:
            block = fin.read(min(CHUNK, remaining))
            if not block:
                sys.exit(f"Error: {src} is smaller than {size} bytes.")
            fout.write(block)
            remaining -= len(block)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    full = file_path(FULL_SIZE)
    download(full, FULL_SIZE)

    print("Creating the smaller files...")
    for size in SIZES[:-1]:
        make_prefix(full, file_path(size), size)

    print("\nFiles ready:")
    for size in SIZES:
        p = file_path(size)
        ok = "OK" if os.path.getsize(p) == size else "WRONG SIZE"
        print(f"  {p:28s} {os.path.getsize(p):>14,d} bytes  {ok}")


if __name__ == "__main__":
    main()
    # Exit immediately: the streaming library can leave background download
    # threads that keep the process alive after the work is done.
    sys.stdout.flush()
    os._exit(0)