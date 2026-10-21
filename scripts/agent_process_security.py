"""Least-privilege environments and a fail-closed macOS motion-render boundary.

Only bundled, reviewed templates may enter this boundary. This is not a general
third-party plugin runner. Loopback is needed by the renderer's local web server;
untrusted code must not be admitted merely because this sandbox exists.
"""
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time


def worker_environment(source=None):
    source = os.environ if source is None else source
    allowed = ('PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL', 'TZ',
               'PIXFUN_VF_ROOT', 'PIXFUN_HYPERFRAMES_BROWSER', 'PIXFUN_BEAUTY_MANIFEST',
               'HF_HOME', 'HUGGINGFACE_HUB_CACHE', 'MLX_METAL_PATH')
    env = {key: source[key] for key in allowed if key in source}
    env.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1',
               HF_HUB_DISABLE_TELEMETRY='1', PYTHONDONTWRITEBYTECODE='1',
               OMP_NUM_THREADS='2', OPENBLAS_NUM_THREADS='2', MKL_NUM_THREADS='2', VECLIB_MAXIMUM_THREADS='2')
    return env


def render_profile(runtime, browser, project, temporary, executable_dirs):
    """No user-home grant, arbitrary network, Keychain or original-media access."""
    read = ['/System', '/usr', '/bin', '/sbin', '/Library/Apple', '/Library/Fonts',
            '/private/var/db/dyld', '/private/var/db/timezone', '/private/etc/fonts',
            str(Path(runtime).resolve()), str(Path(browser).resolve().parents[2]),
            str(Path(project).resolve()), str(Path(temporary).resolve())]
    read += [str(Path(p).resolve()) for p in executable_dirs]
    subpaths = ' '.join('(subpath '+json.dumps(p, ensure_ascii=False)+')' for p in read)
    writes = ' '.join('(subpath '+json.dumps(str(Path(p).resolve()), ensure_ascii=False)+')' for p in (project, temporary))
    return '''(version 1)
(deny default)
(allow process-exec process-fork)
(deny process-info*)
(allow process-info* (target self))
(allow system-sched (target self))
(allow signal (target self))
(allow sysctl-read)
(allow mach-lookup)
(deny mach-lookup (global-name "com.apple.securityd") (global-name "com.apple.secd") (global-name "com.apple.securityd.xpc") (global-name "com.apple.authd"))
(allow mach-register (global-name-prefix "org.chromium."))
(allow mach-register (global-name-prefix "com.google.Chrome.MachPortRendezvousServer."))
(allow iokit-open (iokit-user-client-class "RootDomainUserClient"))
(allow ipc-posix*)
(allow file-read-metadata)
(allow file-read* %s (literal "/") (literal "/Library") (literal "/dev/null") (literal "/dev/random") (literal "/dev/urandom"))
(allow file-write* %s (literal "/dev/null"))
(allow network-inbound (local ip "localhost:*"))
(allow network-outbound (remote ip "localhost:*"))
(allow network-bind (local unix-socket))
''' % (subpaths, writes)


def render_environment(temporary, browser, executable_dirs):
    root = Path(temporary)
    for name in ('home', 'tmp', 'cache'):
        (root/name).mkdir(exist_ok=True)
    return dict(PATH=os.pathsep.join([str(p) for p in executable_dirs]+['/usr/bin', '/bin']),
                HOME=str(root/'home'), CFFIXED_USER_HOME=str(root/'home'), TMPDIR=str(root/'tmp'), MAC_CHROMIUM_TMPDIR=str(root/'tmp'), XDG_CACHE_HOME=str(root/'cache'),
                LANG='en_US.UTF-8', HYPERFRAMES_NO_TELEMETRY='1', DO_NOT_TRACK='1',
                HYPERFRAMES_SKIP_SKILLS='1', HYPERFRAMES_NO_UPDATE_CHECK='1',
                HYPERFRAMES_NO_AUTO_INSTALL='1', HYPERFRAMES_BROWSER_PATH=str(browser))


def run_motion_render(command, runtime, browser, project):
    sandbox = Path('/usr/bin/sandbox-exec')
    if platform.system() != 'Darwin' or not sandbox.is_file():
        raise RuntimeError('Secure local motion rendering is unavailable. No unrestricted fallback was run.')
    helper = Path(__file__).resolve()
    ffmpeg = next((p for p in (helper.parent/'bin/ffmpeg', helper.parent.parent/'build-desktop/media/bin/ffmpeg') if p.is_file()), None)
    if not ffmpeg:
        raise RuntimeError('The bundled media renderer is missing.')
    # Include only required tool directories, never inherit the caller's PATH.
    directories = [Path(runtime).resolve(), Path(ffmpeg).resolve().parent]
    # Chromium's singleton Unix-socket path must fit the macOS path-length limit.
    with tempfile.TemporaryDirectory(prefix='pfm-', dir='/private/tmp') as temporary:
        profile = Path(temporary)/'renderer.sb'
        profile.write_text(render_profile(runtime, browser, project, temporary, directories))
        def audit(status):
            # Operational status only: never record labels, media paths, env or child output.
            with (Path(project)/'security-events.jsonl').open('a',encoding='utf-8') as handle:
                handle.write(json.dumps(dict(time=int(time.time()), policy='motion-isolation-v1', status=status))+'\n')
        audit('started')
        try:
            result = subprocess.run([str(sandbox), '-f', str(profile), *map(str, command)],
                                    cwd=project, env=render_environment(temporary, browser, directories),
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=240)
        except subprocess.TimeoutExpired:
            audit('timeout')
            raise RuntimeError('Isolated motion rendering timed out. No unrestricted retry was made.') from None
        audit('completed' if result.returncode == 0 else 'failed')
        if result.returncode:
            # Child output may include title copy, paths or reflected secret strings.
            raise RuntimeError('Isolated motion rendering failed. Your previous preview is kept; no unrestricted retry was made.')
        return result
