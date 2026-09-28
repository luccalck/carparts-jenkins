ARG JENKINS_VERSION=2.568.3
FROM jenkins/jenkins:${JENKINS_VERSION}-jdk21
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml PLUGINS_FORCE_UPGRADE=true
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
COPY .plugin-cache/ /usr/share/jenkins/ref/plugins/
RUN jenkins-plugin-cli --latest=false --jenkins-update-center-download-url https://ftp.halifax.rwth-aachen.de/jenkins/plugins --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
