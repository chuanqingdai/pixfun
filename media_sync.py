"""Local, opt-in folder/card ingestion into the existing SQLite media library.

Never deletes a source. Copies are published only after SHA-256 verification.
The service stays on loopback; phone pairing requires a separate phone adapter.
"""
import concurrent.futures
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import threading
import tempfile
import time
import uuid


class Paused(Exception): pass


def publish_exclusive(partial, target):
    # macOS RENAME_EXCL works on removable filesystems without hard links.
    if os.uname().sysname == 'Darwin':
        libc=ctypes.CDLL(None,use_errno=True)
        rename=libc.renamex_np
        rename.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint]
        rename.restype=ctypes.c_int
        if rename(os.fsencode(partial),os.fsencode(target),4):
            code=ctypes.get_errno(); raise OSError(code,os.strerror(code))
    else: os.link(partial,target)


def digest(path, cancel=None):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while True:
            if cancel and cancel.is_set(): raise Paused()
            data = stream.read(4*1024*1024)
            if not data: return h.hexdigest()
            h.update(data)


def disk_info(path):
    if not Path('/usr/sbin/diskutil').is_file(): return {}
    try:
        result = subprocess.run(['/usr/sbin/diskutil','info','-plist',str(path)],capture_output=True,timeout=3)
        return plistlib.loads(result.stdout) if not result.returncode else {}
    except (OSError, ValueError, subprocess.TimeoutExpired): return {}


def anchor(path):
    value = Path(path).expanduser()
    if not value.is_absolute() or value.is_symlink(): raise ValueError('Choose a local folder, not a symbolic link.')
    value = value.resolve(strict=True)
    if not value.is_dir() or value == Path('/'): raise ValueError('Choose a media folder or removable card.')
    stat = value.stat(); info = disk_info(value)
    if str(value).startswith('/Volumes/') and not info.get('VolumeUUID'):
        raise ValueError('This volume could not be identified safely. Reconnect it and try again.')
    saved=dict(path=str(value),name=value.name,device=stat.st_dev,inode=stat.st_ino,volume=info.get('VolumeUUID'),verifyVolume=str(value).startswith('/Volumes/'))
    mount=info.get('MountPoint')
    if mount and Path(mount) in (value,*value.parents):
        saved.update(mount=mount,relative=str(value.relative_to(mount)))
    return saved


def relocate_source(saved, mounts):
    """Resolve the same volume and directory, never a same-named replacement."""
    if not saved.get('verifyVolume') or not saved.get('volume'): return None
    relative=saved.get('relative')
    if relative is None:
        parts=Path(saved['path']).parts
        if len(parts)<3 or parts[:2]!=('/','Volumes'): return None
        relative=str(Path(*parts[3:])) if len(parts)>3 else '.'
    if Path(relative).is_absolute() or '..' in Path(relative).parts: return None
    matches=[m for m in mounts if m['volume']==saved['volume']]
    if len(matches)!=1: return None
    mount=Path(matches[0]['path']); candidate=mount/relative
    try:
        if mount.is_symlink() or candidate.resolve()!=candidate or not candidate.is_dir(): return None
        if candidate.stat().st_ino!=saved['inode']: return None
        updated=anchor(candidate)
        if updated.get('volume')!=saved['volume']: return None
        updated.update(mount=str(mount),relative=relative,verifyVolume=True)
        return updated
    except (OSError,ValueError): return None


def connected(saved, verify_volume=True):
    if not saved: return False
    path=Path(saved['path'])
    try:
        if path.is_symlink() or not path.is_dir(): return False
        stat=path.stat()
        if stat.st_ino != saved['inode']: return False
        if verify_volume and saved.get('verifyVolume',str(path).startswith('/Volumes/')):
            return bool(saved.get('volume') and disk_info(path).get('VolumeUUID')==saved['volume'])
        if stat.st_dev == saved['device']: return True
        return bool(saved.get('volume') and disk_info(path).get('VolumeUUID') == saved['volume'])
    except OSError: return False


def overlaps(left, right):
    a,b=Path(left).resolve(),Path(right).resolve()
    return a == b or a in b.parents or b in a.parents


class FolderSourceAdapter:
    def scan(self, source, extensions, cancel):
        root=Path(source['root']['path'])
        if not connected(source['root']): raise ValueError('Source disconnected. Reconnect it and retry.')
        def scan_error(error): raise error
        for directory, folders, files in os.walk(root,followlinks=False,onerror=scan_error):
            if cancel.is_set(): raise Paused()
            folders[:] = sorted(f for f in folders if not f.startswith('.') and not (Path(directory)/f).is_symlink())
            for name in sorted(files):
                path=Path(directory)/name
                if name.startswith('.') or path.suffix.lower() not in extensions or path.is_symlink(): continue
                if root not in path.resolve().parents: continue
                stat=path.stat()
                if stat.st_size>0: yield path,stat


class MediaSync:
    def __init__(self, library, photos, videos, monitor=True):
        self.library=library; self.photos=photos; self.videos=videos
        self.lock=threading.RLock(); self.events={}; self.futures={}; self.archive_future=None; self.active_partials=set()
        self.pool=concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.archives=concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.stopping=threading.Event(); self.adapter=FolderSourceAdapter()
        self.available=[]; self.last_discovery=0; self.seen=set(); self.archive_error=None
        self.archive_waiting=False
        with library.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS sync_sources(id TEXT PRIMARY KEY,record TEXT NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS sync_assets(id TEXT PRIMARY KEY,source_id TEXT NOT NULL,source_key TEXT NOT NULL,record TEXT NOT NULL,UNIQUE(source_id,source_key))')
            db.execute('CREATE TABLE IF NOT EXISTS sync_storage(id TEXT PRIMARY KEY,record TEXT NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS sync_partials(path TEXT PRIMARY KEY,record TEXT NOT NULL)')
        for source in self.sources():
            if source['status'] in ('Waiting','Scanning','Importing','Verifying'):
                automatic=source['automatic'] and not source.get('userPaused',False)
                source.update(status='Waiting to import' if automatic else 'Paused',autoWait=automatic,
                    message='Will continue when the source and save location are connected.' if automatic else 'Import paused after restart. Resume to continue.')
                self.save_source(source)
        self.thread=None
        from phone_sync import PhoneSync
        self.phone_sync=PhoneSync(self)
        from browser_import import BrowserImport
        self.browser_import=BrowserImport(self)
        if monitor:
            self.phone_sync.restore()
            self.thread=threading.Thread(target=self.watch,daemon=True); self.thread.start()

    def sources(self):
        with self.library.connect() as db: return [json.loads(r[0]) for r in db.execute('SELECT record FROM sync_sources ORDER BY rowid')]

    def source(self, key):
        return next((s for s in self.sources() if s['id']==key),None)

    def save_source(self, source):
        with self.library.connect() as db: db.execute('INSERT INTO sync_sources VALUES (?,?) ON CONFLICT(id) DO UPDATE SET record=excluded.record',(source['id'],json.dumps(source)))

    def storage(self):
        with self.library.connect() as db: return {k:json.loads(v) for k,v in db.execute('SELECT id,record FROM sync_storage')}

    def assets(self, source_id=None):
        with self.library.connect() as db:
            rows=db.execute('SELECT record FROM sync_assets'+(' WHERE source_id=?' if source_id else ''),(source_id,) if source_id else ())
            return [json.loads(r[0]) for r in rows]

    def save_asset(self, asset):
        with self.library.connect() as db:
            db.execute('INSERT OR REPLACE INTO sync_assets VALUES (?,?,?,?)',(asset['id'],asset['sourceId'],asset['key'],json.dumps(asset)))

    def busy(self, key=None):
        with self.lock:
            return (getattr(self,'phone_sync',None) is not None and self.phone_sync.busy(key)) or any(not f.done() for k,f in self.futures.items() if key is None or key==k)

    def snapshot(self):
        assets=self.assets()
        ready_counts={}
        for asset in assets:
            if asset.get('status')=='ready':
                key=asset['sourceId']; ready_counts[key]=ready_counts.get(key,0)+1
        sources=[]
        configured_sources=self.sources()
        known_locations={(s['root']['path'],s['root'].get('volume')) for s in configured_sources}
        for s in configured_sources:
            online=connected(s['root'])
            if not online and not self.busy(s['id']) and s['root'].get('verifyVolume') and Path(s['root']['path']).is_dir():
                info=disk_info(s['root']['path'])
                if info.get('VolumeUUID') and info['VolumeUUID']!=s['root'].get('volume') and (s['root']['path'],info['VolumeUUID']) not in known_locations:
                    s={**s,'status':'Source changed','message':'This card no longer matches the saved device. If it was replaced or formatted, add it as a new source to confirm access.'}
            sources.append({k:v for k,v in dict(s,sourcePath=s['root']['path'],readyCount=ready_counts.get(s['id'],0),connected=online,busy=self.busy(s['id']),status=s['status'] if online or self.busy(s['id']) or s.get('userPaused') or s['status']=='Source changed' else 'Offline').items() if k!='root'})
        storage=[]
        for key in ('working','archive'):
            saved=self.storage().get(key)
            online=connected(saved)
            try: free=shutil.disk_usage(saved['path']).free if online else None
            except OSError: free=None; online=False
            storage.append(dict(id=key,name=saved['name'] if saved else 'Not configured',connected=online,
                path=saved['path'] if saved else None,availableBytes=free,enabled=saved.get('enabled',True) if saved else False))
        configured=[s['root']['path'] for s in self.sources() if connected(s['root'])]+[s['path'] for s in self.storage().values()]
        available=[s for s in self.available if not any(overlaps(s['path'],p) for p in configured)]
        phones,wifi=self.phone_sync.snapshot()
        for phone in phones: phone['readyCount']=ready_counts.get(phone['id'],0)
        return dict(devices=sources+phones,storage=storage,available=available,wifi=wifi,phoneImport=self.browser_import.snapshot(),
            archivePending=sum(a.get('status')=='ready' and a.get('archiveStatus')!='completed' for a in assets),
            archiving=bool(self.archive_future and not self.archive_future.done()),archiveError=self.archive_error,archiveWaiting=self.archive_waiting,phoneAvailable=True)

    def storage_target(self, key, path):
        """Validate without persisting; setup can commit source + destination together."""
        target=anchor(path)
        if any(overlaps(target['path'],s['root']['path']) for s in self.sources()): raise ValueError('Storage must be separate from your source folders and cards.')
        if overlaps(target['path'], self.library.directory): raise ValueError('Choose a folder outside Pixfun’s internal library database.')
        other=self.storage().get('archive' if key=='working' else 'working')
        if other and overlaps(target['path'],other['path']): raise ValueError('Working and Archive Storage must be separate folders.')
        target['enabled']=True
        return target

    def configure_storage(self, payload):
        key=payload.get('kind')
        if key not in ('working','archive'): raise ValueError('Choose Working or Archive Storage.')
        with self.lock:
            if self.busy() or self.archive_future and not self.archive_future.done(): raise ValueError('Pause imports and wait for the current archive copy before changing storage.')
            if self.browser_import.session and self.browser_import.session['phase']=='uploading':
                raise ValueError('Finish or cancel the phone import before changing storage.')
            if payload.get('path') is None and key=='archive':
                with self.library.connect() as db: db.execute('DELETE FROM sync_storage WHERE id=?',(key,))
                return
            target=self.storage_target(key,payload.get('path',''))
            with self.library.connect() as db: db.execute('INSERT OR REPLACE INTO sync_storage VALUES (?,?)',(key,json.dumps(target)))
            if key=='archive': self.archive_error=None; self.archive_pending()

    def configure_source(self, payload):
        key=payload.get('id'); source=self.source(key) if key else None
        if key and not source: raise ValueError('This device is no longer configured.')
        import_now=payload.get('importNow',not key and payload.get('automatic',False))
        if not isinstance(import_now,bool): raise ValueError('Choose a valid import action.')
        with self.lock:
            if key and self.busy(key): raise ValueError('Pause this import before changing settings.')
            working=None
            if 'workingPath' in payload:
                if self.busy() or self.archive_future and not self.archive_future.done(): raise ValueError('Wait for current copies before changing the save location.')
                working=self.storage_target('working',payload['workingPath'])
            effective_storage={**self.storage(), **({'working':working} if working else {})}
            root=source['root'] if source else anchor(payload.get('path',''))
            if overlaps(root['path'],self.library.directory): raise ValueError('Choose a source outside Pixfun’s internal library.')
            if any(overlaps(root['path'],v['path']) for v in effective_storage.values()): raise ValueError('Keep the source and save location in separate folders.')
            if not source and any(connected(s['root']) and overlaps(root['path'],s['root']['path']) for s in self.sources()): raise ValueError('This folder or a containing folder is already configured.')
            name=payload.get('name',root['name'])
            if not isinstance(name,str) or not 1<=len(name.strip())<=80: raise ValueError('Use a device name up to 80 characters.')
            kind=payload.get('kind',source['kind'] if source else 'camera')
            if kind not in ('camera','external'): raise ValueError('Phone Wi-Fi sync is not available yet. Choose a card or local folder.')
            for field in ('automatic','photos','videos'):
                if not isinstance(payload.get(field),bool): raise ValueError('Choose valid import settings.')
            if not payload['photos'] and not payload['videos']: raise ValueError('Choose photos, videos, or both.')
            source=source or dict(id=uuid.uuid4().hex,root=root,status='Connected',lastSync=None,
                completed=0,total=0,failed=0,skipped=0,bytes=0,totalBytes=0,message='Ready to import.')
            source.update(name=name.strip(),kind=kind,automatic=payload['automatic'],photos=payload['photos'],videos=payload['videos'])
            # One transaction: invalid/cancelled setup never changes global storage.
            with self.library.connect() as db:
                if working: db.execute('INSERT OR REPLACE INTO sync_storage VALUES (?,?)',('working',json.dumps(working)))
                db.execute('INSERT INTO sync_sources VALUES (?,?) ON CONFLICT(id) DO UPDATE SET record=excluded.record',(source['id'],json.dumps(source)))
            self.seen.add(source['id'])
            if import_now:
                try: self.start(source['id'])
                except ValueError as exc: self.defer_import(source['id'],exc)

    def action(self, payload):
        action=payload.get('action'); key=payload.get('id')
        if action=='phoneImportBegin': self.browser_import.begin(payload)
        elif action=='phoneImportCancel': self.browser_import.cancel_session()
        elif action=='phonePair': self.phone_sync.pair_begin(payload)
        elif action=='phoneCancelPair': self.phone_sync.pairing=None
        elif action=='phoneEnable': self.phone_sync.start()
        elif action=='phoneDisable': self.phone_sync.stop(persist=True)
        elif action in ('phonePause','phoneResume','phoneRemove'): self.phone_sync.phone_action(payload)
        elif action=='discover': self.discover_sources()
        elif action=='storage': self.configure_storage(payload)
        elif action=='configure': self.configure_source(payload)
        elif action=='archive': self.archive_pending()
        elif action=='archiveEnabled':
            if not isinstance(payload.get('enabled'),bool): raise ValueError('Choose a valid archive setting.')
            with self.lock:
                saved=self.storage().get('archive')
                if not saved: raise ValueError('Choose Archive Storage first.')
                saved['enabled']=payload['enabled']
                with self.library.connect() as db: db.execute('UPDATE sync_storage SET record=? WHERE id=?',(json.dumps(saved),'archive'))
            if saved['enabled']: self.archive_pending()
        elif action in ('start','resume','retry'): self.start(key)
        elif action=='pause':
            with self.lock:
                source=self.source(key)
                if not source: raise ValueError('Device not found.')
                if key in self.events: self.events[key].set()
                source.update(status='Paused',userPaused=True,autoWait=False,message='Paused. Completed files are kept.'); self.save_source(source)
        elif action=='remove':
            with self.lock:
                if self.busy(key): raise ValueError('Pause and wait for this import before removing the device.')
                with self.library.connect() as db: db.execute('DELETE FROM sync_sources WHERE id=?',(key,))
                self.seen.discard(key)
        else: raise ValueError('Unknown Media Sync action.')
        return self.snapshot()

    def start(self, key):
        with self.lock:
            if self.stopping.is_set(): raise ValueError('Pixfun is closing. Resume this import next time.')
            if self.phone_sync.busy(): raise ValueError('Wait for the current phone transfer or pause phone sync before importing.')
            source=self.source(key)
            if not source: raise ValueError('Device not found.')
            if self.busy(key): return
            storage=self.storage().get('working')
            if not storage or not connected(storage): raise ValueError('Choose connected Working Storage before importing.')
            if not connected(source['root']): raise ValueError('Source disconnected. Reconnect it and retry.')
            event=threading.Event(); self.events[key]=event
            waiting=self.busy()
            source.update(status='Waiting' if waiting else 'Scanning',autoWait=False,userPaused=False,message='Waiting for another import.' if waiting else 'Checking media. Completed files are kept.')
            self.save_source(source)
            self.futures[key]=self.pool.submit(self.run,key,storage,event)

    def status(self,key,**values):
        with self.lock:
            source=self.source(key)
            if source:
                if self.events.get(key) and self.events[key].is_set() and not self.stopping.is_set(): values['status']='Paused'
                source.update(values); self.save_source(source)

    def defer_import(self,key,error):
        source=self.source(key)
        if not source: return
        storage=self.storage().get('working')
        missing_source=not connected(source['root'])
        missing_storage=not storage or not connected(storage)
        transient=missing_source or missing_storage or self.phone_sync.busy()
        auto=source['automatic'] and not source.get('userPaused',False) and transient
        status=('Waiting for source' if missing_source else 'Waiting for storage' if missing_storage else 'Waiting to import') if auto else 'Needs Attention'
        self.status(key,status=status,autoWait=auto,message=self.friendly(error))

    def cleanup_partials(self):
        # Only ledger-owned scratch files, with matching identity; never scan and
        # delete arbitrary .partial files from a user's storage folder.
        with self.lock, self.library.connect() as db:
            for path,raw in db.execute('SELECT path,record FROM sync_partials').fetchall():
                if path in self.active_partials: continue
                saved=json.loads(raw); file=Path(path)
                if not connected(saved['storage']): continue
                try:
                    if (not file.is_symlink() and Path(saved['storage']['path']) in file.resolve().parents
                            and file.exists() and file.stat().st_ino==saved['inode']): file.unlink()
                    db.execute('DELETE FROM sync_partials WHERE path=?',(path,))
                except OSError: pass

    def copy_verified(self, original, target, expected, source_anchor, target_anchor, cancel, progress=None, expected_sha=None, verifying=None):
        last_volume_check=[0.0]
        def check():
            if cancel.is_set(): raise Paused()
            verify_volume=time.monotonic()-last_volume_check[0]>2
            if not connected(source_anchor,verify_volume): raise ValueError('Source disconnected. Reconnect it and retry.')
            if not connected(target_anchor,verify_volume): raise ValueError('Storage disconnected. Reconnect it and retry.')
            if verify_volume: last_volume_check[0]=time.monotonic()
            if original.is_symlink() or Path(source_anchor['path']) not in original.resolve().parents: raise ValueError('Source file moved outside its configured folder.')
            if target.is_symlink() or Path(target_anchor['path']) not in target.resolve().parents: raise ValueError('Storage location changed. Choose it again.')
        check(); self.cleanup_partials()
        if shutil.disk_usage(target_anchor['path']).free < expected+16*1024*1024: raise ValueError('Not Enough Storage. Free some space and retry.')
        target.parent.mkdir(parents=True,exist_ok=True)
        check()
        with self.lock:
            fd,temporary=tempfile.mkstemp(prefix='.pixfun-copy-',suffix='.partial',dir=target.parent)
            partial=Path(temporary)
            try:
                with self.library.connect() as db:
                    db.execute('INSERT INTO sync_partials VALUES (?,?)',(temporary,json.dumps(dict(storage=target_anchor,inode=os.fstat(fd).st_ino))))
                self.active_partials.add(temporary)
            except Exception:
                os.close(fd); partial.unlink(missing_ok=True); raise
        try:
            with os.fdopen(fd,'wb') as writer, original.open('rb') as reader:
                before=original.stat(); h=hashlib.sha256(); copied=0
                while True:
                    check(); data=reader.read(4*1024*1024)
                    if not data: break
                    writer.write(data); h.update(data); copied+=len(data)
                    if progress: progress(copied)
                writer.flush(); os.fsync(writer.fileno())
            check(); after=original.stat()
            if copied!=expected or (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns): raise ValueError('A source file changed during import. Retry after recording finishes.')
            sha=h.hexdigest()
            if expected_sha and sha!=expected_sha: raise ValueError('Working copy changed. Archive was not marked complete.')
            if verifying: verifying()
            if digest(partial,cancel)!=sha: raise ValueError('File verification failed. Retry this import.')
            check()
            # Never overwrite a file, even after a previous interrupted publish.
            if target.exists():
                if target.stat().st_size != expected or digest(target,cancel)!=sha: raise ValueError('Destination already contains a different file. Choose another storage folder.')
            else:
                publish_exclusive(partial,target)
            return sha
        finally:
            # Only our own temporary file, never originals or finished copies.
            with self.lock: self.active_partials.discard(temporary)
            self.cleanup_partials()

    def run(self,key,storage,event):
        source=self.source(key); current=None
        batch_id=uuid.uuid4().hex
        try:
            if event.is_set(): raise Paused()
            self.status(key,status='Scanning',message='Checking media. Completed files are kept.')
            extensions=(self.photos if source['photos'] else set()) | (self.videos if source['videos'] else set())
            candidates=list(self.adapter.scan(source,extensions,event))
            total=sum(s.st_size for _,s in candidates)
            old={a['key']:a for a in self.assets(key)}
            completed=failed=skipped=done_bytes=0; last_failure=None
            pending=[]
            for path,stat in candidates:
                if event.is_set(): raise Paused()
                relative=str(path.relative_to(source['root']['path']))
                fingerprint=hashlib.sha256(f'{relative}:{stat.st_size}:{stat.st_mtime_ns}'.encode()).hexdigest()
                current=old.get(fingerprint)
                if current and current.get('status')=='ready':
                    # Metadata is only a candidate match; checksum confirms it.
                    target=Path(current['workingPath'])
                    if digest(path,event)==current['sha256'] and (not connected(current['targetStorage']) or
                            target.is_file() and target.stat().st_size==stat.st_size and digest(target,event)==current['sha256']):
                        skipped+=1; done_bytes+=stat.st_size
                        continue
                    # Preserve the previous working copy; never overwrite a changed file.
                    current['key']=fingerprint+'-'+current['id']; self.save_asset(current)
                    current=None
                current=current or dict(id=uuid.uuid4().hex,sourceId=key,key=fingerprint,fileName=path.name,fileSize=stat.st_size,status='pending')
                # Only unpublished files follow a newly selected destination.
                # Finished copies (including offline copies) are never moved.
                if not current.get('workingPath') or not Path(current['workingPath']).exists():
                    current['targetStorage']=storage
                    current['workingPath']=str(Path(storage['path'])/'Pixfun Media'/key/current['id']/path.name)
                self.save_asset(current)
                pending.append((path,stat,current))
            self.status(key,total=len(candidates),totalBytes=total,status='Importing',completed=0,failed=0,skipped=skipped,bytes=done_bytes)
            for path,stat,current in pending:
                if event.is_set(): raise Paused()
                try:
                    current['status']='importing'; self.save_asset(current)
                    target=Path(current['workingPath']); last=[0.0]
                    def progress(count):
                        if time.monotonic()-last[0]>.2:
                            last[0]=time.monotonic(); self.status(key,status='Importing',bytes=done_bytes+count,message=path.name)
                    sha=self.copy_verified(path,target,stat.st_size,source['root'],current['targetStorage'],event,progress,
                        verifying=lambda:self.status(key,status='Verifying',message='Checking the copied file.'))
                    self.status(key,status='Verifying',message='Adding verified media to your library.')
                    result=self.library.register([str(target)])
                    if result['errors'] or not result['items']: raise ValueError('The copy is safe, but library import failed. Retry to finish.')
                    mid=result['items'][0]['id']
                    self.library.patch(mid,syncSourceId=key,syncSourceName=source['name'],syncSourceKind=source['kind'],importBatchId=batch_id,originalFileName=path.name)
                    current.update(status='ready',sha256=sha,mediaId=mid,archiveStatus='pending',error=None)
                    self.save_asset(current); completed+=1; done_bytes+=stat.st_size
                    self.archive_pending()
                except Paused: raise
                except (OSError,ValueError) as exc:
                    current.update(status='failed',error=self.friendly(exc)); self.save_asset(current); failed+=1
                    last_failure=current['error']
                    self.status(key,failed=failed,message=current['error'])
                    if not connected(source['root']) or not connected(current['targetStorage']) or 'Not Enough Storage' in current['error']: raise
                self.status(key,completed=completed,failed=failed,skipped=skipped,bytes=done_bytes)
            self.status(key,status='Needs Attention' if failed else 'Completed',lastSync=time.time(),
                message=last_failure if failed else ('No supported photos or videos found. Check the selected folder and file types.' if not candidates else 'Media imported. Originals are kept.'),
                completed=completed,failed=failed,skipped=skipped,bytes=done_bytes)
        except Paused:
            if current and current.get('status')=='importing': current['status']='pending'; self.save_asset(current)
            saved=self.source(key)
            resume=self.stopping.is_set() and saved and saved['automatic'] and not saved.get('userPaused',False)
            self.status(key,status='Waiting to import' if resume else 'Paused',autoWait=bool(resume),message='Completed files are kept.')
        except Exception as exc: self.defer_import(key,exc)

    @staticmethod
    def friendly(error):
        if isinstance(error,OSError):
            if error.errno in (1,13): return 'Folder access is blocked. Allow Pixfun access in System Settings, then retry.'
            if error.errno==30: return 'Storage is read-only. Choose a writable Working Storage folder and retry.'
            return 'Not Enough Storage. Free some space and retry.' if error.errno==28 else 'Could not read or write a file. Check the connected source and storage, then retry.'
        return str(error)[:180] if isinstance(error,ValueError) else 'Import was interrupted. Completed files are kept. Retry to continue.'

    def archive_pending(self):
        with self.lock:
            if self.stopping.is_set(): return
            storage=self.storage().get('archive')
            if not storage or not storage.get('enabled',True) or not connected(storage) or self.archive_future and not self.archive_future.done(): return
            if not any(a.get('status')=='ready' and a.get('archiveStatus')!='completed' for a in self.assets()): return
            self.archive_error=None; self.archive_waiting=False
            self.archive_future=self.archives.submit(self.archive_run,storage)

    def archive_run(self,storage):
        for asset in self.assets():
            if self.stopping.is_set(): return
            if not self.storage().get('archive',{}).get('enabled',False): return
            if asset.get('status')!='ready' or asset.get('archiveStatus')=='completed': continue
            try:
                original=Path(asset['workingPath']); target=Path(storage['path'])/'Pixfun Archive'/asset['sourceId']/asset['id']/asset['fileName']
                self.copy_verified(original,target,asset['fileSize'],asset['targetStorage'],storage,self.stopping,expected_sha=asset['sha256'])
                with self.lock:
                    latest=next((a for a in self.assets() if a['id']==asset['id']),None)
                    if latest:
                        latest.update(archiveStatus='completed',archivePath=str(target)); self.save_asset(latest)
            except Paused: return
            except Exception as exc:
                self.archive_error=self.friendly(exc)
                self.archive_waiting=not connected(storage) or not connected(asset['targetStorage'])
                # Stop this archive attempt and offer one explicit retry.
                # The verified working copies remain usable throughout.
                return

    def mounted_volumes(self):
        root=Path('/Volumes'); result=[]
        for path in root.iterdir() if root.is_dir() else []:
            if path.is_symlink() or not path.is_dir(): continue
            info=disk_info(path)
            if info.get('VolumeUUID'): result.append(dict(path=str(path),volume=info['VolumeUUID']))
        return result

    def reconcile_sources(self):
        online=set()
        mounts=None
        for source in self.sources():
            if not self.busy(source['id']) and not connected(source['root']) and source['root'].get('verifyVolume'):
                if mounts is None: mounts=self.mounted_volumes()
                moved=relocate_source(source['root'],mounts)
                if moved and not any(overlaps(moved['path'],s['path']) for s in self.storage().values()) and not overlaps(moved['path'],self.library.directory):
                    with self.lock:
                        latest=self.source(source['id'])
                        if latest and not self.busy(source['id']):
                            latest['root']=moved; self.save_source(latest); source=latest
                            self.seen.discard(source['id'])
            if connected(source['root']):
                online.add(source['id'])
                with self.lock:
                    source=self.source(source['id'])
                    if source and (source['id'] not in self.seen or source.get('autoWait')) and source['automatic'] and source['status']!='Paused' and not source.get('userPaused',False) and not self.busy(source['id']):
                        try: self.start(source['id'])
                        except ValueError as exc: self.defer_import(source['id'],exc)
        self.seen=online

    def reconcile_archive(self):
        if self.archive_waiting:
            storage=self.storage().get('archive')
            pending=[a for a in self.assets() if a.get('status')=='ready' and a.get('archiveStatus')!='completed']
            if storage and connected(storage) and all(connected(a['targetStorage']) for a in pending):
                self.archive_error=None; self.archive_waiting=False
        if not self.archive_error: self.archive_pending()

    def discover_sources(self, volume_root=Path('/Volumes')):
        """Read mounted removable volumes only; discovery never configures or imports."""
        found=[]
        configured=[s['root']['path'] for s in self.sources() if connected(s['root'])]
        for path in volume_root.iterdir() if volume_root.is_dir() else []:
            try:
                if path.is_symlink() or not path.is_dir() or any(overlaps(path,p) for p in configured): continue
                info=disk_info(path)
                if info.get('VolumeUUID') and (info.get('RemovableMedia') or info.get('Ejectable')):
                    found.append(dict(id=str(info['VolumeUUID']),name=path.name,path=str(path),
                        kind='camera' if (path/'DCIM').is_dir() else 'external'))
            except (OSError,ValueError): continue
        self.available=sorted(found,key=lambda source:source['name'].casefold())

    def watch(self):
        while not self.stopping.wait(5):
            try:
                self.reconcile_sources()
                self.reconcile_archive()
                if time.monotonic()-self.last_discovery>30:
                    self.cleanup_partials()
                    self.last_discovery=time.monotonic()
                    self.discover_sources()
            except (OSError,ValueError): pass

    def close(self):
        self.stopping.set()
        self.browser_import.stop()
        self.phone_sync.stop()
        with self.lock:
            for event in self.events.values(): event.set()
        if self.thread: self.thread.join(timeout=4)
        self.pool.shutdown(wait=True); self.archives.shutdown(wait=True)
