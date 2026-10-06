pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 40, unit: 'MINUTES')
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        MAVEN_OPTS = '-Xmx384m'
        REGISTRY   = 'localhost:5001'
        IMAGE_NAME = 'turnos-api'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    def sha = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                    def version = sh(returnStdout: true,
                        script: 'mvn -q -B -DforceStdout help:evaluate -Dexpression=project.version').trim()
                    // Immutable tag: <pom version>-<build number>-<commit>
                    env.IMAGE = "${REGISTRY}/${IMAGE_NAME}:${version}-${BUILD_NUMBER}-${sha}"
                }
                echo "Image to build: ${env.IMAGE}"
            }
        }

        stage('Build') {
            steps {
                sh 'mvn -B clean package -DskipTests'
            }
        }

        stage('Test') {
            steps {
                // Unit + integration (H2) tests. A red test stops the pipeline here ("fail early").
                sh 'mvn -B test'
            }
            post {
                always { junit 'target/surefire-reports/*.xml' }
            }
        }

        stage('Coverage Gate') {
            steps {
                // Fails the build if line coverage < 80% (rule lives in pom.xml)
                sh 'mvn -B jacoco:report jacoco:check@coverage-gate'
            }
            post {
                always { recordCoverage tools: [[parser: 'JACOCO', pattern: 'target/site/jacoco/jacoco.xml']] }
            }
        }

        stage('Static Analysis') {
            steps {
                sh 'mvn -B pmd:check@static-analysis'
            }
            post {
                always { archiveArtifacts artifacts: 'target/pmd.xml', allowEmptyArchive: true }
            }
        }

        stage('Package') {
            steps {
                sh 'docker build -t "$IMAGE" .'
            }
        }

        stage('Publish') {
            steps {
                sh 'docker push "$IMAGE"'
            }
        }

        stage('Deploy Staging') {
            steps {
                // Deploys, waits for /actuator/health, rolls back on failure (see scripts/deploy.sh)
                sh 'sh scripts/deploy.sh turnos-staging staging "$IMAGE" 8081'
                // Smoke test: the staging container must answer as "staging"
                sh 'curl -fs http://turnos-staging:8080/api/version | grep -q staging'
            }
        }

        stage('Approval') {
            steps {
                // Continuous DELIVERY: a human decides when production gets the tested image.
                timeout(time: 15, unit: 'MINUTES') {
                    input message: "Deploy ${env.IMAGE} to PRODUCTION?", ok: 'Deploy to production'
                }
            }
        }

        stage('Deploy Production') {
            steps {
                sh 'sh scripts/deploy.sh turnos-prod production "$IMAGE" 8082'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: true, fingerprint: true
        }
        success {
            echo "[SIMULATED NOTIFICATION] Build #${BUILD_NUMBER} OK - ${env.IMAGE} is live."
        }
        failure {
            echo "[SIMULATED NOTIFICATION] Build #${BUILD_NUMBER} FAILED - team notified (Slack/e-mail would go here)."
        }
    }
}
