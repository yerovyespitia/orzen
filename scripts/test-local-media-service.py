#!/usr/bin/env python3
"""Exercise the built macOS service with isolated defaults and media files (Debug build)."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import hashlib
import time
import urllib.error
import urllib.request
import uuid

helper = Path(sys.argv[1]).resolve()
identifier = str(uuid.uuid4())
suite = 'OrzenServiceSmoke.' + identifier
token = 'smoke-token-' + identifier
with socket.socket() as socket_probe:
    socket_probe.bind(('127.0.0.1', 0))
    port = socket_probe.getsockname()[1]
base = f'http://127.0.0.1:{port}/'

def request(path, body=None, authenticated=True, headers=None, method=None):
    h = headers or {}
    if authenticated:
        h['X-Orzen-Token'] = token
    if body is not None:
        h['Content-Type'] = 'application/json'
        body = json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=body, headers=h, method=method)
    return urllib.request.urlopen(req, timeout=3)

with tempfile.TemporaryDirectory(prefix='orzen-service-smoke-') as folder:
    root = Path(folder)
    media_id = str(uuid.uuid4()).upper()
    payload = b'Orzen local media byte-range fixture' * 32
    (root / 'movie.mp4').write_bytes(payload)
    version = dict(id=media_id, catalogID='smoke-movie', contentType='movie',
                   infoHash='abc123', torrentTitle='Smoke Movie', folderRelativePath='.',
                   videoRelativePath='movie.mp4', status='completed', trackInfoVersion=2)
    (root / 'library.json').write_text(json.dumps([version]))
    env = dict(os.environ, ORZEN_SERVICE_TEST_ROOT=folder, ORZEN_SERVICE_TEST_DEFAULTS=suite,
               ORZEN_SERVICE_TEST_PORT=str(port), LLVM_PROFILE_FILE=str(root / 'profile-%p.profraw'))
    args = [str(helper), '-localMedia.serviceMigration.v1', 'YES',
            '-localMedia.accessToken', token, '-localMedia.pairingCode', '654321']
    process = None
    parent = None
    def start():
        p = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            if p.poll() is not None:
                raise AssertionError('Service exited before listening')
            try:
                with request('snapshot') as response:
                    return p, json.load(response)
            except (OSError, urllib.error.URLError):
                time.sleep(.1)
        p.terminate()
        raise AssertionError('Service did not become available')
    try:
        process, first = start()
        assert first['versions'][0]['id'] == media_id
        with request('configuration', {'endpoint': '', 'apiKey': ''}) as response:
            assert json.load(response)['success']
        metadata = dict(id='smoke-movie', title='Smoke Movie', description='Saved catalog metadata', genres=[], cinemetaType='movie')
        with request('metadata', metadata) as response:
            assert json.load(response)['success']
        with request('snapshot') as response:
            assert json.load(response)['versions'][0]['catalogItem']['title'] == metadata['title']
        item = dict(id='smoke-download', title='Smoke Download', description='Test fixture', genres=[], cinemetaType='movie')
        info_hash = hashlib.sha1(identifier.encode()).hexdigest()
        result = dict(id='smoke-result', title='Smoke Download', infoHash=info_hash,
                      downloadURL='magnet:?xt=urn:btih:' + info_hash)
        with request('downloads', dict(item=item, result=result)) as response:
            download = json.load(response)
        download_id = download['id']
        for action in ['pause', 'resume', 'pause']:
            with request('downloads/' + download_id + '/' + action, {}) as response:
                assert json.load(response)['success']
        timestamp = time.time() - 978307200  # Swift Codable Date reference: 2001-01-01.
        membership = dict(collectionID='favorites', item=item, updatedAt=timestamp, isDeleted=False)
        collections = dict(favoriteItems=[item], planToWatchItems=[], watchedItems=[], droppedItems=[], records=[membership])
        with request('collections', {'collections': collections}) as response:
            assert json.load(response)['collections']['favoriteItems'][0]['id'] == item['id']
        deletion = dict(membership, updatedAt=timestamp + 1, isDeleted=True)
        removed = dict(collections, favoriteItems=[], records=[deletion])
        with request('collections', {'collections': removed}) as response:
            assert json.load(response)['collections']['favoriteItems'] == []
        with request('collections', {'collections': collections}) as response:
            assert json.load(response)['collections']['favoriteItems'] == []
        try:
            request('library', authenticated=False)
            raise AssertionError('Unauthenticated access was accepted')
        except urllib.error.HTTPError as error:
            assert error.code == 401
        with request('pair', {'code': '654321'}, authenticated=False) as response:
            assert json.load(response)['token'] == token
        with request('media/' + media_id, headers={'Range': 'bytes=3-15'}) as response:
            assert response.status == 206
            assert response.read() == payload[3:16]
        with request('media/' + media_id, method='HEAD') as response:
            assert int(response.headers['Content-Length']) == len(payload)
            assert response.read() == b''
        duplicate = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert duplicate.wait(timeout=10) == 0
        process.terminate()
        process.wait(timeout=10)
        process, second = start()
        assert second['instanceID'] != first['instanceID']
        assert next(v for v in second['versions'] if v['id'] == media_id)['status'] == 'completed'
        assert next(v for v in second['versions'] if v['id'] == download_id)['status'] == 'paused'
        with request('downloads/' + download_id, method='DELETE') as response:
            assert json.load(response)['success']
        with request('pair', {'code': '654321'}, authenticated=False) as response:
            assert json.load(response)['token'] == token
        with request('downloads/' + media_id, method='DELETE') as response:
            assert json.load(response)['success']
        with request('snapshot') as response:
            snapshot = json.load(response)
            assert snapshot['versions'] == []
            assert snapshot['revision'] > second['revision']
        assert not (root / 'movie.mp4').exists()
        process.terminate()
        process.wait(timeout=10)
        root.mkdir(exist_ok=True)
        queued = dict(version, status='queued', videoRelativePath=None)
        before = json.dumps([queued])
        (root / 'library.json').write_text(before)
        with socket.socket() as occupied:
            occupied.bind(('127.0.0.1', 0))
            occupied.listen()
            busy_env = dict(env, ORZEN_SERVICE_TEST_PORT=str(occupied.getsockname()[1]))
            process = subprocess.Popen(args, env=busy_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(1)
            assert process.poll() is None
            assert (root / 'library.json').read_text() == before, 'Busy port must not start downloads or change the library'
        print('PASS: authentication, pairing, library, byte ranges, singleton, download pause/resume, collection tombstones, restart, deletion and busy-port protection')
    finally:
        for p in (parent, process):
            if p is not None and p.poll() is None:
                p.terminate()
                p.wait(timeout=10)
        subprocess.run(['defaults', 'delete', suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
