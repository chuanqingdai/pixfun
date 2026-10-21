"""Bound FFmpeg decoder, filter and encoder thread pools for local media work."""
from pathlib import Path


def bounded_command(args):
    args = [str(value) for value in args]
    if not args or Path(args[0]).name != 'ffmpeg' or '-i' not in args:
        return args
    # Commands here have one output. FFmpeg options apply to the next input or
    # output, so a single leading -threads does not bound the encoder/next input.
    thread_flags = {'-threads', '-threads:v', '-threads:a', '-filter_threads', '-filter_complex_threads'}
    clean = []
    iterator = iter(args)
    for value in iterator:
        if value in thread_flags:
            next(iterator)
        else:
            clean.append(value)
    result = [clean[0], '-filter_threads', '2', '-filter_complex_threads', '2']
    for value in clean[1:]:
        if value == '-i': result.extend(['-threads', '2'])
        result.append(value)
    result[-1:-1] = ['-threads', '2']
    return result
