"""Isolated copy/SQLite tests. No user library, cards, or originals are modified."""
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from media_sync import MediaSync, Paused, anchor, connected, digest, relocate_source
from desktop_service import Library, PHOTO, VIDEO


class MediaSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='pixfun-sync-test-')
        self.root=Path(self.temp.name).resolve()
        self.card=self.root/'card'; self.work=self.root/'work'; self.archive=self.root/'archive'
        for path in (self.card,self.work,self.archive): path.mkdir()
        self.library=Library(self.root/'database')
        # These tests isolate ingestion from asynchronous AI/media analysis.
        self.library.enqueue=lambda _:None
        self.sync=MediaSync(self.library,PHOTO,VIDEO,monitor=False)
        self.sync.configure_storage(dict(kind='working',path=str(self.work)))

    def tearDown(self):
        self.sync.close(); self.library.close(); self.temp.cleanup()

    def configure(self,automatic=False,**values):
        self.sync.configure_source(dict(path=str(self.card),name='Test card',kind='camera',automatic=automatic,photos=True,videos=True,**values))
        return self.sync.sources()[0]['id']

    def run_import(self,key):
        self.sync.start(key); self.sync.futures[key].result(timeout=10)
        return self.sync.source(key)

    def test_progress_updates_keep_one_card_per_source_in_creation_order(self):
        first=self.configure()
        other=self.root/'other-card'; other.mkdir()
        self.sync.configure_source(dict(path=str(other),name='Second card',kind='camera',automatic=False,photos=True,videos=True))
        ids=[s['id'] for s in self.sync.snapshot()['devices']]
        for phase in ('Scanning','Importing','Verifying','Paused','Needs Attention','Completed'):
            self.sync.status(first,status=phase,completed=1,total=2)
            snapshot=self.sync.snapshot()
            self.assertEqual([s['id'] for s in snapshot['devices']],ids)
            self.assertEqual(snapshot['devices'][0]['status'],phase)
            self.assertEqual(snapshot['devices'][0]['sourcePath'],str(self.card))
            self.assertNotIn('root',snapshot['devices'][0])

    def test_ready_media_remains_visible_during_next_scan(self):
        (self.card/'photo.jpg').write_bytes(b'original')
        key=self.configure(); self.run_import(key)
        self.sync.status(key,status='Scanning',completed=0,skipped=0,total=0)
        self.assertEqual(self.sync.snapshot()['devices'][0]['readyCount'],1)

    def test_phone_progress_preserves_card_order_and_hides_credentials(self):
        for key in ('phone-one','phone-two'):
            self.sync.phone_sync.save(dict(id=key,automatic=True,status='Connected',credential='test-private'))
        self.sync.phone_sync.save(dict(id='phone-one',automatic=True,status='Importing',credential='test-private'))
        phones,_=self.sync.phone_sync.snapshot()
        self.assertEqual([p['id'] for p in phones],['phone-one','phone-two'])
        self.assertTrue(all('credential' not in p for p in phones))

    def test_first_setup_commits_destination_and_source_then_imports(self):
        with self.library.connect() as db: db.execute('DELETE FROM sync_storage')
        (self.card/'photo.jpg').write_bytes(b'original')
        key=self.configure(workingPath=str(self.work),importNow=True)
        self.sync.futures[key].result(timeout=10)
        self.assertEqual(self.sync.storage()['working']['path'],str(self.work))
        self.assertEqual(self.sync.source(key)['completed'],1)
        self.assertEqual((self.card/'photo.jpg').read_bytes(),b'original')

    def test_invalid_setup_does_not_change_destination_or_add_source(self):
        destination=self.root/'new-work'; destination.mkdir()
        original=self.sync.storage()
        base=dict(path=str(self.card),name='Card',kind='camera',automatic=False,photos=True,videos=True,workingPath=str(destination))
        for invalid in (dict(name=''),dict(photos=False,videos=False),dict(workingPath=str(self.card))):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                self.sync.configure_source({**base,**invalid})
            self.assertEqual(self.sync.storage(),original)
            self.assertEqual(self.sync.sources(),[])

    def test_setup_cannot_change_destination_during_copy(self):
        original=self.sync.storage()
        with patch.object(self.sync,'busy',return_value=True), self.assertRaises(ValueError):
            self.configure(workingPath=str(self.archive))
        self.assertEqual(self.sync.storage(),original)
        self.assertEqual(self.sync.sources(),[])

    def test_discovery_lists_real_mounted_names_without_configuring(self):
        volumes=self.root/'Volumes'; volumes.mkdir()
        for name in ('EOS_CARD','Travel SSD','Internal','Unknown'): (volumes/name).mkdir()
        (volumes/'EOS_CARD'/'DCIM').mkdir()
        (volumes/'Alias').symlink_to(volumes/'EOS_CARD')
        def info(path):
            name=Path(path).name
            if name=='Unknown': return {}
            return dict(VolumeUUID=name,RemovableMedia=name=='EOS_CARD',Ejectable=name=='Travel SSD')
        with patch('media_sync.disk_info',side_effect=info):
            self.sync.discover_sources(volumes)
        self.assertEqual([(v['name'],v['kind']) for v in self.sync.available],[('EOS_CARD','camera'),('Travel SSD','external')])
        self.assertEqual(self.sync.sources(),[])
        self.assertEqual(self.library.list(),[])
        (volumes/'Travel SSD').rmdir()
        with patch('media_sync.disk_info',side_effect=info): self.sync.discover_sources(volumes)
        self.assertEqual([v['name'] for v in self.sync.available],['EOS_CARD'])

    def test_discovery_action_is_read_only(self):
        storage=self.sync.storage()
        with patch.object(self.sync,'discover_sources') as discover:
            self.sync.action(dict(action='discover'))
        discover.assert_called_once_with()
        self.assertEqual(self.sync.storage(),storage)
        self.assertEqual(self.sync.sources(),[])

    def test_verified_incremental_import_and_restart(self):
        (self.card/'photo.jpg').write_bytes(b'first-photo')
        (self.card/'clip.MOV').write_bytes(b'first-video')
        (self.card/'ignore.txt').write_text('do not import')
        key=self.configure()
        result=self.run_import(key)
        self.assertEqual((result['status'],result['completed']),('Completed',2))
        self.assertEqual(len(self.library.list()),2)
        for asset in self.sync.assets():
            self.assertEqual(digest(Path(asset['workingPath'])),asset['sha256'])
            self.assertEqual(Path(asset['workingPath']).name,asset['fileName'])
            self.assertTrue((self.card/asset['fileName']).exists())
        self.sync.close(); self.sync=MediaSync(self.library,PHOTO,VIDEO,monitor=False)
        (self.card/'next.jpg').write_bytes(b'new-photo')
        result=self.run_import(key)
        self.assertEqual((result['completed'],result['skipped']),(1,2))
        self.assertEqual(len(self.library.list()),3)

    def test_pause_resume_keeps_completed_files(self):
        for name in ('a.jpg','b.jpg'): (self.card/name).write_bytes(name.encode())
        key=self.configure(); original=self.sync.copy_verified; count=[0]
        def pause_second(*args,**kwargs):
            count[0]+=1
            if count[0]==2:
                self.sync.events[key].set(); raise Paused()
            return original(*args,**kwargs)
        with patch.object(self.sync,'copy_verified',side_effect=pause_second):
            result=self.run_import(key)
        self.assertEqual(result['status'],'Paused'); self.assertEqual(len(self.library.list()),1)
        result=self.run_import(key)
        self.assertEqual((result['completed'],result['skipped']),(1,1))
        self.assertEqual(len(self.library.list()),2)

    def test_restart_marks_incomplete_job_paused(self):
        key=self.configure(); self.sync.status(key,status='Importing',total=5,completed=2)
        self.sync.close(); self.sync=MediaSync(self.library,PHOTO,VIDEO,monitor=False)
        restored=self.sync.source(key)
        self.assertEqual((restored['status'],restored['completed']),('Paused',2))

    def test_not_enough_storage_can_retry(self):
        (self.card/'photo.jpg').write_bytes(b'original'); key=self.configure()
        with patch('media_sync.shutil.disk_usage') as space:
            space.return_value.free=0
            result=self.run_import(key)
        self.assertEqual(result['status'],'Needs Attention')
        self.assertIn('Not Enough Storage',result['message'])
        self.assertEqual(len(self.library.list()),0)
        self.assertEqual(self.run_import(key)['completed'],1)
        self.assertEqual((self.card/'photo.jpg').read_bytes(),b'original')

    def test_destination_disconnect_stops_and_reconnect_retries(self):
        original=self.card/'large.mov'; original.write_bytes(b'x'*(5*1024*1024))
        key=self.configure(); copy=self.sync.copy_verified; unplugged=self.root/'unplugged'
        def disconnect(*args,**kwargs):
            args=list(args)
            def progress(_):
                if self.work.exists(): self.work.rename(unplugged)
            args[6]=progress
            return copy(*args,**kwargs)
        with patch.object(self.sync,'copy_verified',side_effect=disconnect):
            result=self.run_import(key)
        self.assertEqual(result['status'],'Needs Attention')
        self.assertFalse(self.work.exists(),'Never recreate an unmounted root')
        self.assertEqual(len(self.library.list()),0)
        unplugged.rename(self.work)
        self.assertEqual(self.run_import(key)['completed'],1)
        self.assertEqual(original.stat().st_size,5*1024*1024)
        self.assertEqual(list(self.work.rglob('*.partial')),[])

    def test_changed_file_with_same_metadata_preserves_original_copy(self):
        path=self.card/'photo.jpg'; path.write_bytes(b'aaaa'); stamp=path.stat()
        key=self.configure(); self.run_import(key)
        first=Path(self.sync.assets()[0]['workingPath'])
        path.write_bytes(b'bbbb'); os.utime(path,ns=(stamp.st_atime_ns,stamp.st_mtime_ns))
        self.assertEqual(self.run_import(key)['completed'],1)
        self.assertEqual(first.read_bytes(),b'aaaa')
        self.assertEqual(len(self.library.list()),2)
        self.assertEqual(len(self.sync.assets()),2)
        self.assertEqual(self.run_import(key)['skipped'],1)

    def test_archive_is_verified_and_does_not_block_library(self):
        (self.card/'a.jpg').write_bytes(b'photo'); key=self.configure()
        self.sync.configure_storage(dict(kind='archive',path=str(self.archive)))
        self.assertEqual(self.run_import(key)['completed'],1)
        self.sync.archive_pending()
        self.sync.archive_future.result(timeout=10)
        asset=self.sync.assets()[0]
        self.assertEqual(asset['archiveStatus'],'completed')
        self.assertEqual(Path(asset['archivePath']).read_bytes(),b'photo')
        self.assertEqual(len(self.library.list()),1)
        self.sync.action(dict(action='archiveEnabled',enabled=False))
        (self.card/'b.jpg').write_bytes(b'other'); self.run_import(key)
        self.assertEqual(self.sync.snapshot()['archivePending'],1)
        self.sync.action(dict(action='archiveEnabled',enabled=True))
        self.sync.archive_future.result(timeout=10)
        self.assertEqual(self.sync.snapshot()['archivePending'],0)

    def test_archive_corruption_not_published(self):
        (self.card/'a.jpg').write_bytes(b'photo'); key=self.configure(); self.run_import(key)
        asset=self.sync.assets()[0]; Path(asset['workingPath']).write_bytes(b'wrong')
        self.sync.configure_storage(dict(kind='archive',path=str(self.archive)))
        self.sync.archive_future.result(timeout=10)
        self.assertEqual(self.sync.snapshot()['archivePending'],1)
        self.assertEqual(list(self.archive.rglob('*.jpg')),[])
        self.assertEqual(self.sync.source(key)['status'],'Completed')

    def test_storage_change_only_affects_new_files(self):
        (self.card/'a.jpg').write_bytes(b'photo'); key=self.configure(); self.run_import(key)
        first=self.sync.assets()[0]['workingPath']; other=self.root/'other'; other.mkdir()
        self.sync.configure_storage(dict(kind='working',path=str(other)))
        (self.card/'b.jpg').write_bytes(b'new'); self.run_import(key)
        self.assertTrue(Path(first).is_file())
        new=next(a for a in self.sync.assets() if a['fileName']=='b.jpg')
        self.assertTrue(new['workingPath'].startswith(str(other)))

    def test_unsafe_overlap_and_symlinks_rejected(self):
        key=self.configure()
        with self.assertRaises(ValueError): self.sync.configure_storage(dict(kind='working',path=str(self.card)))
        with self.assertRaises(ValueError): self.sync.configure_source(dict(path=str(self.work),name='Bad',kind='camera',automatic=False,photos=True,videos=True))
        (self.card/'outside.jpg').symlink_to(ROOT/'public/media/travel/luxury.jpg')
        self.assertEqual(self.run_import(key)['completed'],0)
        link=self.root/'link'; link.symlink_to(self.work)
        with self.assertRaises(ValueError): anchor(str(link))

    def test_copy_never_overwrites_existing_destination(self):
        src=self.card/'a.jpg'; src.write_bytes(b'new')
        target=self.work/'a.jpg'; target.write_bytes(b'old')
        with self.assertRaises(ValueError): self.sync.copy_verified(src,target,3,anchor(self.card),anchor(self.work),threading.Event())
        self.assertEqual(target.read_bytes(),b'old')
        self.assertEqual(list(self.work.glob('*.partial')),[])

    def test_verification_failure_is_retryable(self):
        (self.card/'a.jpg').write_bytes(b'photo'); key=self.configure()
        real=digest
        with patch('media_sync.digest',side_effect=lambda path,cancel=None:'wrong' if path.suffix=='.partial' else real(path,cancel)):
            result=self.run_import(key)
        self.assertEqual(result['status'],'Needs Attention')
        self.assertEqual(len(self.library.list()),0)
        self.assertEqual(self.run_import(key)['completed'],1)

    def test_automatic_reconnect_does_not_import_unconfigured_source(self):
        (self.card/'a.jpg').write_bytes(b'photo'); key=self.configure(automatic=True)
        self.sync.futures[key].result(timeout=10)
        offline=self.root/'offline'; self.card.rename(offline); self.sync.reconcile_sources()
        self.assertEqual(self.sync.snapshot()['devices'][0]['status'],'Offline')
        offline.rename(self.card); (self.card/'b.jpg').write_bytes(b'new')
        self.sync.reconcile_sources(); self.sync.futures[key].result(timeout=10)
        self.assertEqual((self.sync.source(key)['completed'],self.sync.source(key)['skipped']),(1,1))
        self.sync.action(dict(action='remove',id=key))
        self.assertEqual(len(self.library.list()),2)
        self.assertEqual(len(list(self.card.glob('*.jpg'))),2)
        self.assertEqual(self.sync.snapshot()['devices'],[])

    def test_unexpected_failure_reaches_attention_not_endless_spinner(self):
        key=self.configure()
        with patch.object(self.sync.adapter,'scan',side_effect=RuntimeError('private internals')):
            result=self.run_import(key)
        self.assertEqual(result['status'],'Needs Attention')
        self.assertNotIn('private internals',result['message'])

    def test_setup_without_working_storage_retains_configuration(self):
        with self.library.connect() as db: db.execute('DELETE FROM sync_storage')
        key=self.configure(automatic=True)
        self.assertEqual(self.sync.source(key)['status'],'Waiting for storage')
        self.assertIn('Working Storage',self.sync.source(key)['message'])

    def test_auto_import_continues_when_save_location_returns(self):
        (self.card/'a.jpg').write_bytes(b'photo')
        offline=self.root/'offline-work'; self.work.rename(offline)
        key=self.configure(automatic=True)
        self.assertEqual(self.sync.source(key)['status'],'Waiting for storage')
        self.sync.reconcile_sources()
        self.assertNotIn(key,self.sync.futures)
        offline.rename(self.work)
        self.sync.reconcile_sources(); self.sync.futures[key].result(timeout=10)
        self.assertEqual(self.sync.source(key)['completed'],1)
        with patch.object(self.sync,'start') as start:
            self.sync.reconcile_sources(); start.assert_not_called()

    def test_auto_mid_copy_disconnect_recovers_without_manual_retry(self):
        (self.card/'a.jpg').write_bytes(b'photo')
        key=self.configure(automatic=True,importNow=False)
        offline=self.root/'offline-work'; copy=self.sync.copy_verified
        def disconnect(*args,**kwargs):
            self.work.rename(offline)
            return copy(*args,**kwargs)
        with patch.object(self.sync,'copy_verified',side_effect=disconnect):
            result=self.run_import(key)
        self.assertEqual(result['status'],'Waiting for storage')
        self.assertTrue(result['autoWait'])
        offline.rename(self.work)
        self.sync.reconcile_sources(); self.sync.futures[key].result(timeout=10)
        self.assertEqual(len(self.library.list()),1)
        self.assertEqual(list(self.work.rglob('*.partial')),[])

    def test_user_pause_survives_reconnect_and_restart(self):
        key=self.configure(automatic=True,importNow=False)
        self.sync.action(dict(action='pause',id=key))
        offline=self.root/'offline-card'; self.card.rename(offline)
        self.sync.reconcile_sources()
        self.assertEqual(self.sync.snapshot()['devices'][0]['status'],'Paused')
        offline.rename(self.card)
        self.sync.close(); self.sync=MediaSync(self.library,PHOTO,VIDEO,monitor=False)
        with patch.object(self.sync,'start') as start:
            self.sync.reconcile_sources(); start.assert_not_called()

    def test_restart_recovers_automatic_incomplete_job(self):
        (self.card/'a.jpg').write_bytes(b'photo')
        key=self.configure(automatic=True,importNow=False)
        self.sync.status(key,status='Importing')
        self.sync.close(); self.sync=MediaSync(self.library,PHOTO,VIDEO,monitor=False)
        self.assertEqual(self.sync.source(key)['status'],'Waiting to import')
        self.sync.reconcile_sources(); self.sync.futures[key].result(timeout=10)
        self.assertEqual(self.sync.source(key)['completed'],1)

    def test_disk_full_does_not_loop_automatic_retries(self):
        (self.card/'a.jpg').write_bytes(b'photo')
        key=self.configure(automatic=True,importNow=False)
        with patch('media_sync.shutil.disk_usage') as usage:
            usage.return_value.free=0; self.run_import(key)
        self.assertEqual(self.sync.source(key)['status'],'Needs Attention')
        with patch.object(self.sync,'start') as start:
            self.sync.reconcile_sources(); self.sync.reconcile_sources(); start.assert_not_called()

    def test_source_rename_preserves_identity_and_rejects_reformatted_card(self):
        saved=anchor(self.card); saved.update(verifyVolume=True,volume='card-uuid',relative='.')
        renamed=self.root/'Renamed card'; self.card.rename(renamed)
        mounts=[dict(path=str(renamed),volume='card-uuid')]
        with patch('media_sync.disk_info',return_value=dict(VolumeUUID='card-uuid',MountPoint=str(renamed))):
            updated=relocate_source(saved,mounts)
            self.assertEqual(updated['path'],str(renamed))
            self.assertTrue(connected(updated))
            self.assertIsNone(relocate_source(saved,mounts+mounts),'Ambiguous volume IDs must not auto-connect')
        with patch('media_sync.disk_info',return_value=dict(VolumeUUID='new-uuid')):
            self.assertIsNone(relocate_source(saved,mounts))
        self.assertIsNone(relocate_source(saved,[dict(path=str(renamed),volume='new-uuid')]))

    def test_source_subfolder_relocation_rejects_symlink_or_replacement(self):
        folder=self.card/'DCIM'; folder.mkdir()
        saved=anchor(folder); saved.update(verifyVolume=True,volume='card-uuid',relative='DCIM')
        renamed=self.root/'Renamed'; self.card.rename(renamed)
        mounts=[dict(path=str(renamed),volume='card-uuid')]
        with patch('media_sync.disk_info',return_value=dict(VolumeUUID='card-uuid',MountPoint=str(renamed))):
            self.assertEqual(relocate_source(saved,mounts)['path'],str(renamed/'DCIM'))
            (renamed/'DCIM').rename(renamed/'old'); (renamed/'DCIM').symlink_to(renamed/'old')
            self.assertIsNone(relocate_source(saved,mounts))
            (renamed/'DCIM').unlink(); (renamed/'DCIM').mkdir()
            self.assertIsNone(relocate_source(saved,mounts))

    def test_renamed_card_reconnects_without_duplicate_configuration(self):
        (self.card/'a.jpg').write_bytes(b'photo')
        key=self.configure(automatic=True,importNow=False)
        source=self.sync.source(key); source['root'].update(verifyVolume=True,volume='card-uuid',relative='.')
        self.sync.save_source(source)
        renamed=self.root/'Renamed'; self.card.rename(renamed)
        with patch.object(self.sync,'mounted_volumes',return_value=[dict(path=str(renamed),volume='card-uuid')]), patch('media_sync.disk_info',return_value=dict(VolumeUUID='card-uuid',MountPoint=str(renamed))):
            self.sync.reconcile_sources(); self.sync.futures[key].result(timeout=10)
        self.assertEqual(len(self.sync.sources()),1)
        self.assertEqual(self.sync.source(key)['root']['path'],str(renamed))
        self.assertEqual(len(self.library.list()),1)

    def test_archive_disconnect_recovers_only_when_drives_return(self):
        (self.card/'a.jpg').write_bytes(b'photo'); key=self.configure(); self.run_import(key)
        offline=self.root/'offline-archive'; copy=self.sync.copy_verified
        def disconnect(*args,**kwargs):
            self.archive.rename(offline); return copy(*args,**kwargs)
        with patch.object(self.sync,'copy_verified',side_effect=disconnect):
            self.sync.configure_storage(dict(kind='archive',path=str(self.archive)))
            self.sync.archive_future.result(timeout=10)
        self.assertTrue(self.sync.snapshot()['archiveWaiting'])
        self.sync.reconcile_archive()
        self.assertEqual(self.sync.snapshot()['archivePending'],1)
        offline.rename(self.archive); self.sync.reconcile_archive()
        self.sync.archive_future.result(timeout=10)
        self.assertEqual(self.sync.snapshot()['archivePending'],0)
        self.assertIsNone(self.sync.snapshot()['archiveError'])

    def test_same_mount_name_is_not_device_identity(self):
        saved=anchor(self.card); saved.update(verifyVolume=True,volume='original-card')
        with patch('media_sync.disk_info',return_value={'VolumeUUID':'another-card'}):
            self.assertFalse(connected(saved),'A reused device number and root inode must not authorize another card')
        with patch('media_sync.disk_info',return_value={'VolumeUUID':'original-card'}):
            self.assertTrue(connected(saved))

    def test_reformatted_card_requires_explicit_new_source(self):
        key=self.configure(automatic=True,importNow=False)
        source=self.sync.source(key); source['root'].update(verifyVolume=True,volume='original-card',relative='.')
        self.sync.save_source(source)
        with patch('media_sync.disk_info',return_value={'VolumeUUID':'replacement'}), patch.object(self.sync,'mounted_volumes',return_value=[dict(path=str(self.card),volume='replacement')]):
            with patch.object(self.sync,'start') as start:
                self.sync.reconcile_sources(); start.assert_not_called()
            device=self.sync.snapshot()['devices'][0]
        self.assertEqual(device['status'],'Source changed')
        self.assertIn('add it as a new source',device['message'])

    def test_editing_device_does_not_start_an_import(self):
        key=self.configure(automatic=True); self.sync.futures[key].result(timeout=10)
        (self.card/'new.jpg').write_bytes(b'new')
        self.sync.configure_source(dict(id=key,name='Renamed card',kind='camera',automatic=True,photos=True,videos=True))
        self.assertEqual(len(self.library.list()),0)
        self.assertFalse(self.sync.busy(key))

    def test_manual_device_add_and_import_is_one_explicit_action(self):
        (self.card/'new.jpg').write_bytes(b'new')
        key=self.configure(importNow=True)
        self.sync.futures[key].result(timeout=10)
        self.assertEqual(self.sync.source(key)['completed'],1)
        self.assertFalse(self.sync.source(key)['automatic'])
        self.assertEqual(self.library.list()[0]['syncSourceName'],'Test card')
        self.assertEqual(self.library.list()[0]['syncSourceKind'],'camera')
        self.assertTrue(self.library.list()[0]['importBatchId'])

    def test_failed_pending_copy_uses_new_working_storage(self):
        (self.card/'photo.jpg').write_bytes(b'photo'); key=self.configure()
        with patch('media_sync.shutil.disk_usage') as space:
            space.return_value.free=0; self.run_import(key)
        other=self.root/'replacement'; other.mkdir()
        self.sync.configure_storage(dict(kind='working',path=str(other)))
        self.assertEqual(self.run_import(key)['completed'],1)
        self.assertTrue(self.sync.assets()[0]['workingPath'].startswith(str(other)))

    def test_offline_completed_working_copy_is_not_duplicated(self):
        (self.card/'photo.jpg').write_bytes(b'photo'); key=self.configure(); self.run_import(key)
        self.work.rename(self.root/'unplugged')
        other=self.root/'new-working'; other.mkdir()
        self.sync.configure_storage(dict(kind='working',path=str(other)))
        result=self.run_import(key)
        self.assertEqual((result['completed'],result['skipped']),(0,1))
        self.assertEqual(len(self.library.list()),1)
        self.assertEqual(list(other.rglob('*.jpg')),[])

    def test_archive_failure_has_reason_and_explicit_retry(self):
        (self.card/'photo.jpg').write_bytes(b'photo'); key=self.configure(); self.run_import(key)
        with patch('media_sync.shutil.disk_usage') as space:
            space.return_value.free=0
            self.sync.configure_storage(dict(kind='archive',path=str(self.archive)))
            self.sync.archive_future.result(timeout=10)
        self.assertIn('Not Enough Storage',self.sync.snapshot()['archiveError'])
        self.assertEqual(self.sync.source(key)['status'],'Completed')
        self.sync.action(dict(action='archive')); self.sync.archive_future.result(timeout=10)
        self.assertIsNone(self.sync.snapshot()['archiveError'])
        self.assertEqual(self.sync.snapshot()['archivePending'],0)

    def test_resume_checks_before_replacing_progress(self):
        (self.card/'photo.jpg').write_bytes(b'photo'); key=self.configure(); self.run_import(key)
        entered=threading.Event(); release=threading.Event(); scan=self.sync.adapter.scan
        def delayed(*args):
            entered.set(); release.wait(timeout=5); yield from scan(*args)
        with patch.object(self.sync.adapter,'scan',side_effect=delayed):
            self.sync.start(key)
            try:
                self.assertTrue(entered.wait(timeout=5))
                source=self.sync.source(key)
                self.assertEqual((source['status'],source['completed']),('Scanning',1))
            finally: release.set()
            self.sync.futures[key].result(timeout=10)
        self.assertEqual(self.sync.source(key)['skipped'],1)

    def test_queue_is_honest_and_can_be_paused(self):
        key=self.configure(); other=self.root/'card2'; other.mkdir()
        self.sync.configure_source(dict(path=str(other),name='Second',kind='camera',automatic=False,photos=True,videos=True))
        second=next(s['id'] for s in self.sync.sources() if s['id']!=key)
        entered=threading.Event(); release=threading.Event(); scan=self.sync.adapter.scan
        def delayed(*args):
            entered.set(); release.wait(timeout=5); yield from scan(*args)
        with patch.object(self.sync.adapter,'scan',side_effect=delayed):
            self.sync.start(key)
            try:
                self.assertTrue(entered.wait(timeout=5))
                self.sync.start(second)
                self.assertEqual(self.sync.source(second)['status'],'Waiting')
                self.sync.action(dict(action='pause',id=second))
            finally: release.set()
            self.sync.futures[key].result(timeout=10); self.sync.futures[second].result(timeout=10)
        self.assertEqual(self.sync.source(second)['status'],'Paused')

    def test_second_card_with_same_mount_name_can_be_configured(self):
        with patch('media_sync.disk_info',return_value={'VolumeUUID':'first'}): first=self.configure()
        source=self.sync.source(first); source['root']['verifyVolume']=True; self.sync.save_source(source)
        with patch('media_sync.disk_info',return_value={'VolumeUUID':'second'}):
            self.sync.configure_source(dict(path=str(self.card),name='Second card',kind='camera',automatic=False,photos=True,videos=True))
            self.sync.available=[dict(id='second',name='Card',path=str(self.card))]
            self.assertEqual(len(self.sync.snapshot()['devices']),2)
            self.assertEqual(self.sync.snapshot()['devices'][0]['status'],'Offline')

    def test_empty_and_permission_errors_are_actionable(self):
        key=self.configure()
        self.assertIn('No supported photos or videos',self.run_import(key)['message'])
        with patch.object(self.sync.adapter,'scan',side_effect=PermissionError(13,'denied')):
            self.assertIn('Allow Pixfun access',self.run_import(key)['message'])


if __name__=='__main__': unittest.main()
