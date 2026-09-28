import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'scripts' / 'aws-release.py'
spec = importlib.util.spec_from_file_location('aws_release', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AwsSafetyTests(unittest.TestCase):
    def test_valid_digest(self):
        uri = '667230721680.dkr.ecr.us-east-1.amazonaws.com/carparts-api'
        module.validate_image(uri + '@sha256:' + 'a' * 64, uri)

    def test_tag_not_accepted_as_digest(self):
        with self.assertRaises(ValueError):
            module.validate_image('registry/repo:latest', 'registry/repo')

    def test_other_repo_rejected(self):
        with self.assertRaises(ValueError):
            module.validate_image('evil/repo@sha256:' + 'a' * 64, 'registry/repo')

    def test_commit_validation(self):
        module.validate_commit('a' * 40)
        for value in ['main', '$(id)', 'a' * 39]:
            with self.assertRaises(ValueError):
                module.validate_commit(value)

    def test_remote_command_contains_no_credentials(self):
        command = module.remote_command('print("ok")', {'image': 'repo@sha256:' + 'a' * 64})
        self.assertNotIn('AWS_SECRET', command)
        self.assertNotIn('aws_session_token', command)
        self.assertTrue(command.startswith('sudo python3 -c '))

    def test_production_requires_approval(self):
        with self.assertRaises(ValueError):
            module.require_approval({})
        module.require_approval({'APPROVED_BY': 'admin', 'APPROVED_AT': '2026-09-28T00:00:00Z'})


if __name__ == '__main__':
    unittest.main()
