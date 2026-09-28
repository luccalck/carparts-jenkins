# Carparts — Jenkins com AWS

Projeto de laboratório de DevOps, 2ADS. Lucca Castilho Costa, RA 26179873.

API Node.js com dados fictícios, pipeline Jenkins e publicação no Amazon ECR/EC2. A adaptação AWS foi aceita pelo professor, conforme informado pelo aluno. Não utiliza dados do ERP.

## Organização

- `src/`: API HTTP, `/health` e `/orders`.
- `test/`: testes da API, métricas e validações da publicação AWS.
- `jenkins/`: controller LTS, plugins e configuração como código.
- `Jenkinsfile.ci`: qualidade de branches, sem credenciais de nuvem.
- `Jenkinsfile.aws`: qualidade, publicação, homologação, aprovação e produção de laboratório.
- `scripts/aws-release.py`: ECR e comando remoto SSM.
- `scripts/ec2-deploy.py`: implantação, smoke e restauração na EC2.
- `Jenkinsfile` e `scripts/release.sh`: referência Azure original, não executar para AWS.

## Execução local da API

Node.js 24 recomendado:

```bash
npm ci
npm test
npm start
```

Abra `http://localhost:3000/health`. Esse comando não publica na AWS.

## Jenkins local

Docker Desktop em modo Linux e PowerShell 7:

1. Copie `.env.example` para `.env` e configure três senhas locais distintas. Não publique esse arquivo.
2. Execute `pwsh -File jenkins/BAIXAR_PLUGINS.ps1`.
3. Execute `docker compose up -d --build controller`.
4. Execute `docker compose --profile agents build`.
5. Execute `pwsh -File INICIAR_AGENTS.ps1`.
6. Abra `http://localhost:8082` e execute `pwsh -File VERIFICAR_JENKINS.ps1`.

O controller tem zero executores; builds rodam nos agents. O Jenkins não é exposto à Internet.

## Publicação AWS

Prepare ECR privado com tags imutáveis e EC2 Amazon Linux 2023 com Docker, LabRole e SSM Online. A EC2 precisa acessar ECR por HTTPS. Libere 3000/3001 somente para o IP do operador. A região, URI e Instance ID estão em `Jenkinsfile.aws` e precisam ser substituídos em outra conta.

Na pasta Jenkins `carparts-release`, cadastre três Secret text: `aws-lab-access-key`, `aws-lab-secret-key` e `aws-lab-session-token`. Use os valores temporários do Learner Lab, nunca chaves permanentes ou valores em Git.

Execute `pwsh -File CONFIGURAR_AWS.ps1` para criar o job. Primeiro execute com `PREFLIGHT_ONLY=true`. Depois execute com as duas opções desmarcadas. Confira o digest e o commit da homologação antes de aprovar. Produção usa o mesmo digest, sem reconstrução da imagem. `ROLLBACK=true` exige aprovação e uma revisão anterior real.

Credenciais expiradas interrompem o pipeline. Atualize os três valores no cofre antes de nova execução. Não inclua `.env`, chaves `.pem`, caches de plugins ou configurações Docker de autenticação na entrega.

A identidade `release-manager` pode usar credenciais somente nos jobs da pasta `carparts-release`. A CI de branches e PRs roda como `ci-user` e não recebe os segredos AWS. O deploy remoto usa o LabRole da instância, sem transmitir chaves no comando SSM.

Se uma credencial for compartilhada em chat ou captura, trate-a como exposta. Substitua os valores temporários e consulte o administrador do laboratório para revogação; terminar uma sessão não deve ser tomado como garantia de revogação imediata.

## Limites do laboratório

Homologação e produção são dois containers na mesma EC2, portas 3000/3001. Não representam isolamento empresarial. HTTP é usado somente para dados fictícios com origem restrita; uso real exigiria TLS e arquitetura própria.

O job local `validacao-local` não publica na nuvem. Prints, execuções e métricas devem corresponder a resultados reais. Webhook GitHub não alcança localhost: use polling enquanto não houver endpoint seguro de webhook. Não exponha o Jenkins apenas para permitir webhook.

## Testes adicionais

```bash
python3 -m unittest discover -s test -p 'test_aws*.py'
```

Os testes de segurança não substituem deploy, aprovação ou rollback. Histórico de execução e evidências ficam no Jenkins e na entrega da atividade, não são simulados pelo código.
