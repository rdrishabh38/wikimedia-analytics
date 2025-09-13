# ~/wikimedia-poc/justfile

# This is the default command that runs when you just type 'just'
default: help

# --- Help ---

## 📜 Displays this help message
help:
    @just --list

# --- Daily Development ---

## ⏯️ PAUSE: Stops the running K3d cluster (fastest way to stop)
pause:
    k3d cluster stop wikimedia-poc-dev

## ▶️ RESUME: Resumes the cluster from a paused state
resume:
    k3d cluster start wikimedia-poc-dev

## 🩺 STATUS: Checks the status of the cluster and all services
status:
    @echo "--- Checking K3d Nodes ---"
    @kubectl get nodes
    @echo "\n--- Checking Deployed Pods ---"
    @kubectl get pods -A

# --- Connection Management (NEW) ---

## 🔌 CONNECT: Starts port-forwarding to Grafana & Prometheus in the background
connect:
    @echo "--- Starting port forwarding... ---"
    # This pipeline finds the Grafana pod, gets its name, strips the 'pod/' prefix,
    # and pipes the clean name directly into the port-forward command.
    @kubectl get pod -n {{MONITORING_NS}} -l "app.kubernetes.io/name=grafana" -o name | sed 's|pod/||' | xargs -I {} kubectl port-forward -n {{MONITORING_NS}} {} 8080:3000 &

    # This does the same for the Prometheus pod.
    @kubectl get pod -n {{MONITORING_NS}} -l "app.kubernetes.io/name=prometheus" -o name | sed 's|pod/||' | xargs -I {} kubectl port-forward -n {{MONITORING_NS}} {} 9090:9090 &
    
    @sleep 2
    @echo "\n✅ Grafana is now available at: http://localhost:8080"
    @echo "   Username: admin"
    @echo -n "   Password: "
    @kubectl get secret -n {{MONITORING_NS}} {{PROMETHEUS_RELEASE}}-grafana -o=jsonpath='{.data.admin-password}' | base64 --decode; echo ""
    @echo "\n✅ Prometheus is now available at: http://localhost:9090"
    @echo "\nRun 'just disconnect' to stop port forwarding."

## 🔌 DISCONNECT: Stops all background kubectl port-forward processes
disconnect:
    @echo "--- Stopping all kubectl port-forward processes ---"
    @pkill -f "kubectl port-[f]orward" || echo "No active port-forward processes found."
    @echo "✅ Disconnected."


# --- Full Lifecycle ---

## 🚀 ALL: Creates the entire environment (Infrastructure + Application)
all: app-deploy
    @echo "\n✅ Full environment and application are UP!"

## ⛔ CLEAN: Destroys the entire environment completely
clean: app-delete infra-down
    @echo "\n🔥 Full environment has been destroyed."

### 🏗️ INFRA-UP: Creates just the infrastructure (K3d, Kafka, Monitoring, Dashboards)
infra-up: monitoring-dashboards
    @echo "\n✅ Full infrastructure is UP and ready!"

## 🔥 INFRA-DOWN: Destroys just the infrastructure
infra-down:
    @echo "--- Destroying K3d cluster ---"
    cd {{TF_DIR}} && terragrunt destroy --auto-approve

# --- Application Lifecycle ---

## 📦 APP-BUILD: Builds the consumer app and imports it into the cluster
app-build:
    @echo "--- Building and importing application image (disabling cache) ---"
    docker build --no-cache -t {{APP_IMAGE}} ./app
    k3d image import {{APP_IMAGE}} -c wikimedia-poc-dev

## 🚢 APP-DEPLOY: Deploys the consumer application to Kubernetes
app-deploy: infra-up app-build
    @echo "--- Deploying application ---"
    kubectl apply -f {{APP_YAML}}

## 📃 APP-LOGS: Views the logs of the running consumer application
app-logs:
    @echo "--- Tailing application logs (Ctrl+C to exit) ---"
    kubectl logs -f -n {{KAFKA_NS}} -l app=wikimedia-consumer

## 🗑️ APP-DELETE: Deletes the consumer application from Kubernetes
app-delete:
    @echo "--- Deleting application ---"
    kubectl delete -f {{APP_YAML}} --ignore-not-found=true

# --- Individual Infrastructure Components (Dependencies) ---

# Variables for reuse
TF_DIR                  := "./environment/dev"
KAFKA_NS                := "kafka"
KAFKA_YAML              := "./helm/kafka-cluster.yaml"
STRIMZI_VERSION         := "0.41.0"
STRIMZI_RELEASE         := "strimzi-kafka-operator"
APP_IMAGE               := "wikimedia-consumer:0.1"
APP_YAML                := "./app/deployment.yaml"
MONITORING_NS           := "monitoring"
PROMETHEUS_RELEASE      := "prometheus"
KAFKA_EXPORTER_RELEASE  := "kafka-exporter"
GRAFANA_DASHBOARD_YAML  := "./helm/grafana-kafka-incoming-dashboard.yaml"

# 1. Create the K3d cluster
cluster:
    cd {{TF_DIR}} && terragrunt apply --auto-approve

# 2. Install the Strimzi CRDs
crds: cluster
    kubectl apply -f https://github.com/strimzi/strimzi-kafka-operator/releases/download/{{STRIMZI_VERSION}}/strimzi-crds-{{STRIMZI_VERSION}}.yaml

# 3. Add Helm repositories
helm-repos:
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

# 4. Install the Strimzi Operator
operator: crds helm-repos
    helm upgrade {{STRIMZI_RELEASE}} strimzi/strimzi-kafka-operator \
      --install \
      --namespace {{KAFKA_NS}} \
      --create-namespace \
      --version {{STRIMZI_VERSION}} \
      --skip-crds \
      --set networkPolicy.generate=false

# 5. Deploy the Kafka cluster
kafka: operator
    kubectl apply -f {{KAFKA_YAML}}

# 6. Deploy the Schema Registry
schema-registry: kafka
    helm upgrade schema-registry bitnami/schema-registry \
      --install \
      --namespace {{KAFKA_NS}} \
      --set kafka.bootstrapServers="PLAINTEXT://my-cluster-kafka-brokers.kafka.svc:9092"

# 7. Deploy the Monitoring Stack
monitoring-up: schema-registry
    @echo "--- Deploying Prometheus & Grafana ---"
    helm upgrade {{PROMETHEUS_RELEASE}} prometheus-community/kube-prometheus-stack \
      --install \
      --namespace {{MONITORING_NS}} \
      --create-namespace \
      -f helm/prometheus-values.yaml
    @echo "--- Deploying Kafka Exporter using kubectl ---"
    kubectl apply -f helm/kafka-exporter-deployment.yaml

# 8. Deploy Grafana Dashboards
monitoring-dashboards: monitoring-up
    @echo "--- Deploying Grafana Dashboards ---"
    kubectl apply -f {{GRAFANA_DASHBOARD_YAML}}
