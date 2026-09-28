// Pipeline from SCM: somente main revisada, executado como release-manager.
// Credenciais azure-sp somente na pasta carparts-release.
pipeline {
  agent none
  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 90, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '30'))
    skipDefaultCheckout(true)
  }
  parameters {
    string(name: 'AZURE_SUBSCRIPTION', defaultValue: '', description: 'ID da assinatura de laboratório')
    string(name: 'AZURE_TENANT', defaultValue: '', description: 'ID do tenant')
    string(name: 'RESOURCE_GROUP', defaultValue: 'rg-carparts-ci-lab')
    string(name: 'ACR_NAME', defaultValue: '', description: 'ACR existente, sem .azurecr.io')
    string(name: 'HOMOLOG_APP', defaultValue: 'carparts-homol')
    string(name: 'PROD_APP', defaultValue: 'carparts-prod-lab')
  }
  environment {
    AZURE_SUBSCRIPTION = "${params.AZURE_SUBSCRIPTION}"
    AZURE_TENANT = "${params.AZURE_TENANT}"
    RESOURCE_GROUP = "${params.RESOURCE_GROUP}"
    ACR_NAME = "${params.ACR_NAME}"
    HOMOLOG_APP = "${params.HOMOLOG_APP}"
    PROD_APP = "${params.PROD_APP}"
  }
  stages {
    stage('Fonte revisada') {
      agent { label 'lint' }
      steps {
        checkout scm
        script {
          if (!(env.GIT_BRANCH in ['main', 'origin/main'])) error('Release aceita somente main revisada.')
          env.RELEASE_COMMIT = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
          env.COMMIT_AT = sh(script: 'git show -s --format=%cI HEAD', returnStdout: true).trim()
        }
        stash name: 'source', includes: '**/*', excludes: '.git/**,.env*,node_modules/**,reports/**,secrets/**'
      }
    }
    stage('Qualidade') {
      parallel {
        stage('Sintaxe') {
          agent { label 'lint' }
          steps { deleteDir(); unstash 'source'; sh 'npm ci --ignore-scripts && npm run lint' }
        }
        stage('Testes') {
          agent { label 'test' }
          steps { deleteDir(); unstash 'source'; sh 'npm ci --ignore-scripts && mkdir -p reports && npm run test:ci' }
          post { always { junit testResults: 'reports/tests.xml', allowEmptyResults: false } }
        }
      }
    }
    stage('Imagem') {
      when { beforeAgent true; expression { env.GIT_BRANCH in ['main', 'origin/main'] } }
      agent { label 'release' }
      steps {
        deleteDir(); unstash 'source'
        sh 'sh scripts/release.sh build'
      }
    }
    stage('Publicação ACR') {
      when { beforeAgent true; expression { env.GIT_BRANCH in ['main', 'origin/main'] } }
      agent { label 'release' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'AZURE_CLIENT_ID', passwordVariable: 'AZURE_CLIENT_SECRET')]) {
          sh 'sh scripts/release.sh publish'
        }
        script { env.IMAGE_REF = readFile('.release/image.txt').trim() }
        stash name: 'image-metadata', includes: '.release/**'
        archiveArtifacts artifacts: '.release/image.txt', fingerprint: true
      }
    }
    stage('Homologação') {
      agent { label 'release' }
      options { timeout(time: 15, unit: 'MINUTES') }
      steps {
        withCredentials([usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'AZURE_CLIENT_ID', passwordVariable: 'AZURE_CLIENT_SECRET')]) {
          sh 'sh scripts/release.sh homolog'
        }
      }
    }
    stage('Aprovação registrada') {
      agent none
      options { timeout(time: 30, unit: 'MINUTES') }
      steps {
        script {
          env.APPROVED_BY = input(message: "Promover ${env.IMAGE_REF} para produção de laboratório?", submitter: 'release-manager,admin', submitterParameter: 'APROVADOR').toString()
          env.APPROVED_AT = new Date().format("yyyy-MM-dd'T'HH:mm:ssXXX")
          echo "Aprovador: ${env.APPROVED_BY}; horário: ${env.APPROVED_AT}; imagem: ${env.IMAGE_REF}"
        }
      }
    }
    stage('Produção de laboratório') {
      agent { label 'release' }
      options { timeout(time: 15, unit: 'MINUTES') }
      steps {
        unstash 'image-metadata'
        withCredentials([usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'AZURE_CLIENT_ID', passwordVariable: 'AZURE_CLIENT_SECRET')]) {
          sh 'sh scripts/release.sh production'
        }
        archiveArtifacts artifacts: '.release/*.json,.release/*.txt', fingerprint: true
      }
    }
  }
  post {
    success { echo 'Release concluída. Registrar implantação e incidentes na coleta E6.' }
    unsuccessful { echo 'Release interrompida. Sem aprovação não há promoção. Consulte o digest anterior para rollback.' }
    always { echo "Build ${env.BUILD_NUMBER}; commit ${env.RELEASE_COMMIT ?: 'não disponível'}; resultado ${currentBuild.currentResult}" }
  }
}
