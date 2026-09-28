"""Executado como root via SSM; nenhuma chave AWS e transportada no comando."""
import base64
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


def smoke(port, commit):
    last = None
    for _ in range(30):
        try:
            with urlopen(f'http://127.0.0.1:{port}/health', timeout=3) as response:
                data = json.load(response)
                if response.status == 200 and data.get('status') == 'ok' and data.get('commit') == commit:
                    return data
        except Exception as error:
            last = error
        time.sleep(2)
    raise RuntimeError(f'Smoke falhou na porta {port}: {last}')


def inspect(name):
    result = subprocess.run(['docker', 'inspect', name], capture_output=True, text=True)
    return json.loads(result.stdout)[0] if result.returncode == 0 else None


def start(name, port, image):
    run(['docker', 'run', '-d', '--name', name, '--restart', 'unless-stopped',
         '--memory', '256m', '--cpus', '0.5', '--security-opt', 'no-new-privileges',
         '--cap-drop', 'ALL', '--read-only', '--tmpfs', '/tmp:rw,noexec,nosuid,size=16m',
         '--log-opt', 'max-size=5m', '--log-opt', 'max-file=2', '-p', f'{port}:3000', image])


def main():
    payload = json.loads(base64.b64decode(sys.argv[1]))
    action, image, commit, uri = (payload[key] for key in ('action', 'image', 'commit', 'uri'))
    if action not in ('homolog', 'production', 'rollback'):
        raise ValueError('Acao invalida')
    if not re.fullmatch(re.escape(uri) + r'@sha256:[0-9a-f]{64}', image) or not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Imagem ou commit invalido')
    state_dir = Path('/opt/carparts-lab')
    state_dir.mkdir(mode=0o700, exist_ok=True)
    name = 'carparts-homol' if action == 'homolog' else 'carparts-prod'
    port = 3000 if action == 'homolog' else 3001
    state_file = state_dir / (name + '.json')
    old = inspect(name)
    previous = None
    if old:
        previous = {'image': old['Config']['Image'], 'commit': old['Config']['Labels']['org.opencontainers.image.revision']}
    if action == 'rollback':
        history = json.loads(state_file.read_text())
        if not history.get('previous'):
            raise ValueError('Nao ha versao anterior real para rollback')
        image, commit = history['previous']['image'], history['previous']['commit']
        if not re.fullmatch(re.escape(uri) + r'@sha256:[0-9a-f]{64}', image):
            raise ValueError('Digest anterior fora do repositorio autorizado')
    elif action == 'production':
        homol = json.loads((state_dir / 'carparts-homol.json').read_text())
        if homol['image'] != image or homol['commit'] != commit:
            raise ValueError('Imagem nao corresponde a homologacao')
        smoke(3000, commit)
    registry = uri.split('/')[0]
    with tempfile.TemporaryDirectory(prefix='carparts-ecr-') as config:
        import os
        env = dict(os.environ, DOCKER_CONFIG=config)
        password = run(['aws', 'ecr', 'get-login-password', '--region', payload['region']])
        run(['docker', 'login', '--username', 'AWS', '--password-stdin', registry], input=password, env=env)
        del password
        run(['docker', 'pull', image], env=env)
    candidate = name + '-candidate'
    if inspect(candidate):
        raise RuntimeError('Candidato anterior existe: investigue antes de outra publicacao')
    try:
        run(['docker', 'run', '-d', '--name', candidate, '--memory', '256m', '--cap-drop', 'ALL',
             '--security-opt', 'no-new-privileges', '-p', '127.0.0.1::3000', image])
        candidate_data = inspect(candidate)
        candidate_port = candidate_data['NetworkSettings']['Ports']['3000/tcp'][0]['HostPort']
        smoke(candidate_port, commit)
    finally:
        if inspect(candidate):
            run(['docker', 'rm', '-f', candidate])
    if old:
        run(['docker', 'rm', '-f', name])
    try:
        start(name, port, image)
        smoke(port, commit)
        actual = inspect(name)['Config']['Image']
        if actual != image:
            raise RuntimeError('Digest implantado nao corresponde ao solicitado')
    except Exception:
        if inspect(name):
            run(['docker', 'rm', '-f', name])
        if previous:
            start(name, port, previous['image'])
            smoke(port, previous['commit'])
        raise
    record = dict(action=action, image=image, commit=commit, port=port, previous=previous,
                  deployed_at=datetime.now(timezone.utc).isoformat(), health=smoke(port, commit))
    temp = state_file.with_suffix('.tmp')
    temp.write_text(json.dumps(record, indent=2))
    temp.replace(state_file)
    print('CARPARTS_RESULT=' + json.dumps(record))


if __name__ == '__main__':
    main()
