"""Release AWS. Credenciais somente no ambiente fornecido pelo Jenkins."""
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time


def validate_commit(commit):
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Commit deve ser um SHA Git completo.')


def validate_image(image, uri):
    if not re.fullmatch(re.escape(uri) + r'@sha256:[0-9a-f]{64}', image):
        raise ValueError('Somente digest SHA256 do repositorio configurado e permitido.')


def require_approval(env):
    if not env.get('APPROVED_BY') or not env.get('APPROVED_AT'):
        raise ValueError('Promocao/rollback de producao exige aprovacao registrada.')


def remote_command(source, payload):
    encoded = base64.b64encode(source.encode()).decode()
    data = base64.b64encode(json.dumps(payload).encode()).decode()
    loader = f"import base64,sys;sys.argv=['deploy','{data}'];exec(compile(base64.b64decode('{encoded}'),'<deploy>','exec'))"
    return 'sudo python3 -c ' + shlex.quote(loader)


def aws(*args):
    result = subprocess.run(['aws', *args, '--region', os.environ['AWS_REGION'], '--output', 'json'],
                            check=True, capture_output=True, text=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def preflight():
    uri = os.environ['ECR_URI']
    match = re.fullmatch(r'(\d{12})\.dkr\.ecr\.(us-east-1)\.amazonaws\.com/(carparts-api)', uri)
    if not match or os.environ['AWS_REGION'] != match[2]:
        raise ValueError('Repositorio/regiao fora do escopo do laboratorio.')
    identity = aws('sts', 'get-caller-identity')
    if identity['Account'] != match[1]:
        raise ValueError('Conta AWS difere da conta do ECR.')
    repo = aws('ecr', 'describe-repositories', '--repository-names', match[3])['repositories'][0]
    if repo['imageTagMutability'] != 'IMMUTABLE':
        raise ValueError('ECR deve usar tags imutaveis.')
    instance = aws('ec2', 'describe-instances', '--instance-ids', os.environ['EC2_INSTANCE_ID'])['Reservations'][0]['Instances'][0]
    names = [t['Value'] for t in instance.get('Tags', []) if t['Key'] == 'Name']
    if names != ['carparts-jenkins-lab'] or instance['State']['Name'] != 'running':
        raise ValueError('EC2 precisa ser carparts-jenkins-lab e estar running.')
    managed = aws('ssm', 'describe-instance-information', '--filters',
                  json.dumps([{'Key': 'InstanceIds', 'Values': [os.environ['EC2_INSTANCE_ID']]}]))
    if not managed['InstanceInformationList'] or managed['InstanceInformationList'][0]['PingStatus'] != 'Online':
        raise ValueError('SSM nao esta Online.')
    print('PRECHECK OK: conta, ECR imutavel, EC2 correta e SSM Online')
    return match[3], instance.get('PublicIpAddress')


def deploy(action):
    if action in ('production', 'rollback'):
        require_approval(os.environ)
    image = Path('.release/image.txt').read_text().strip()
    validate_image(image, os.environ['ECR_URI'])
    validate_commit(os.environ['RELEASE_COMMIT'])
    payload = dict(action=action, image=image, commit=os.environ['RELEASE_COMMIT'],
                   uri=os.environ['ECR_URI'], region=os.environ['AWS_REGION'])
    source = Path('scripts/ec2-deploy.py').read_text()
    result = aws('ssm', 'send-command', '--instance-ids', os.environ['EC2_INSTANCE_ID'],
                 '--document-name', 'AWS-RunShellScript', '--timeout-seconds', '600',
                 '--parameters', json.dumps({'commands': [remote_command(source, payload)], 'executionTimeout': ['600']}))
    command_id = result['Command']['CommandId']
    print(f'SSM command: {command_id}; etapa: {action}', flush=True)
    deadline = time.monotonic() + 660
    while time.monotonic() < deadline:
        time.sleep(5)
        try:
            status = aws('ssm', 'get-command-invocation', '--command-id', command_id,
                         '--instance-id', os.environ['EC2_INSTANCE_ID'])
        except subprocess.CalledProcessError as error:
            if 'InvocationDoesNotExist' in error.stderr:
                continue
            raise
        if status['Status'] in ('Pending', 'InProgress', 'Delayed'):
            continue
        Path(f'.release/ssm-{action}.json').write_text(json.dumps(status, indent=2))
        print(status.get('StandardOutputContent', ''))
        if status['Status'] != 'Success':
            print(status.get('StandardErrorContent', ''), file=sys.stderr)
            raise RuntimeError(f'SSM {action}: {status["Status"]}')
        lines = status['StandardOutputContent'].splitlines()
        record = json.loads(next(line[len('CARPARTS_RESULT='):] for line in reversed(lines) if line.startswith('CARPARTS_RESULT=')))
        record.update(build=os.environ['BUILD_NUMBER'], commit_at=os.environ.get('COMMIT_AT'),
                      approved_by=os.environ.get('APPROVED_BY'), approved_at=os.environ.get('APPROVED_AT'),
                      instance_id=os.environ['EC2_INSTANCE_ID'], ssm_command_id=command_id)
        Path(f'.release/{action}.json').write_text(json.dumps(record, indent=2))
        print(f'SMOKE OK: HTTP 200, {record["commit"]}, {record["image"]}')
        return
    raise TimeoutError('SSM nao concluiu no prazo; confira o comando antes de executar novamente.')


def main():
    os.environ['AWS_PAGER'] = ''
    os.environ.setdefault('AWS_REGION', 'us-east-1')
    action = sys.argv[1]
    Path('.release').mkdir(exist_ok=True)
    if action == 'preflight':
        preflight()
        return
    validate_commit(os.environ['RELEASE_COMMIT'])
    if action == 'publish':
        repo, _ = preflight()
        tag = f'{os.environ["BUILD_NUMBER"]}-{os.environ["RELEASE_COMMIT"]}'
        ref = os.environ['ECR_URI'] + ':' + tag
        subprocess.run(['docker', 'build', '--build-arg', 'COMMIT_SHA=' + os.environ['RELEASE_COMMIT'], '-t', ref, '.'], check=True)
        registry = os.environ['ECR_URI'].split('/')[0]
        with tempfile.TemporaryDirectory(prefix='carparts-docker-') as config:
            env = dict(os.environ, DOCKER_CONFIG=config)
            password = subprocess.run(['aws', 'ecr', 'get-login-password', '--region', os.environ['AWS_REGION']],
                                      check=True, capture_output=True).stdout
            subprocess.run(['docker', 'login', '--username', 'AWS', '--password-stdin', registry], input=password, env=env, check=True)
            del password
            subprocess.run(['docker', 'push', ref], env=env, check=True)
        digest = aws('ecr', 'describe-images', '--repository-name', repo, '--image-ids', 'imageTag=' + tag)['imageDetails'][0]['imageDigest']
        image = os.environ['ECR_URI'] + '@' + digest
        validate_image(image, os.environ['ECR_URI'])
        Path('.release/image.txt').write_text(image + '\n')
        print('Imagem publicada: ' + image)
    elif action in ('homolog', 'production', 'rollback'):
        deploy(action)
    else:
        raise ValueError('Acao invalida.')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        # AWS CLI nao inclui chaves em seus erros normais; nunca imprimir ambiente.
        print(error.stderr or f'Comando falhou com codigo {error.returncode}', file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
