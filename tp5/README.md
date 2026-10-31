# Trabajo Práctico Observabilidad

**Esta es la guía paso a paso para reproducir la arquitectura solicitada en la práctica.**

Antes de comenzar, se debe tener instalado y actualizado Docker, Minikube, Kubectl y Helm. Los comandos se ejecutan desde una terminal Bash (Linux/WSL) y, salvo que se indique lo contrario, desde la raíz del repositorio.

### Preparación del Entorno

Se inicia Minikube con 4 CPU y 8192 MB de memoria, se agregan los repositorios de Helm correspondientes y se crean los *namespaces* que se utilizarán:

```bash
minikube start --cpus 4 --memory 8192 --driver docker
```

```bash
helm repo add grafana https://grafana.github.io/helm-charts
```

```bash
helm repo add prometheus https://prometheus-community.github.io/helm-charts
```

```bash
kubectl create namespace gamecloud
```

```bash
kubectl create namespace observabilidad
```

### Despliegue de la API

Se construye la imagen de la API dentro de Minikube y se instala el *chart* en el *namespace* correspondiente:

```bash
minikube image build -t gamecloud-ranking:1.0 app/
```

```bash
helm install gamecloud-ranking charts/gamecloud-ranking/ -n gamecloud
```

Para verificar el despliegue y acceder a la API desde el equipo local:

```bash
kubectl get all -n gamecloud
```

```bash
kubectl port-forward svc/gamecloud-ranking -n gamecloud 8080:80
```

*Se debe dejar este último comando ejecutándose en una terminal y realizar las pruebas desde otra.*

```bash
curl http://localhost:8080/ranking
```

```bash
curl http://localhost:8080/metrics
```

Para consultar los *logs* de uno de los *pods* de la API:

```bash
kubectl get pods -n gamecloud
```

```bash
kubectl logs <nombre-pod> -n gamecloud
```

Los *logs* de la aplicación se generan en formato JSON.

### Prometheus y Grafana

Se utiliza el archivo `values-kube-prometheus-stack.yaml`, ubicado en `observabilidad/`, con las configuraciones solicitadas. Entre ellas, se deshabilita Alertmanager, se limita la memoria de Grafana a 1 Gi, se configura Loki como *datasource* adicional y se deshabilitan los tres componentes del Control Plane que no exponen sus métricas hacia la red del nodo en esta configuración de Minikube:

```yaml
alertmanager:
  enabled: false

grafana:
  resources:
    limits:
      memory: 1Gi
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki.observabilidad.svc.cluster.local:3100
      access: proxy
      isDefault: false

kubeEtcd:
  enabled: false
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
```

Luego se instala el *chart* en el *namespace* `observabilidad`:

```bash
helm install prometheus prometheus/kube-prometheus-stack -n observabilidad -f values-kube-prometheus-stack.yaml --version 92.11.0
```

Para verificar el estado de los componentes:

```bash
kubectl get pods -n observabilidad
```

Se puede acceder a Prometheus y Grafana mediante la ejecución del comando `port-forward`:

```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n observabilidad 9090:9090
```

```bash
kubectl port-forward svc/prometheus-grafana -n observabilidad 3000:80
```

Prometheus queda disponible en `http://localhost:9090` y Grafana en `http://localhost:3000`. El usuario de Grafana es `admin` mientras que la contraseña se puede consultar con:

```bash
kubectl get secret prometheus-grafana -n observabilidad -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

Dentro de Prometheus, se debe ingresar a **Status** y luego a **Target Health** para comprobar que los *targets* habilitados se encuentren en estado UP.

### ServiceMonitor de la API

Dentro de `charts/gamecloud-ranking/templates/` se agrega el *template* `service-monitor.yaml`, que permite que Prometheus descubra automáticamente las métricas de la API. El recurso debe seleccionar el Service de GameCloud, incluir la etiqueta `release: prometheus` y utilizar el puerto `http`, la ruta `/metrics` y un intervalo de 15 segundos:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ .Release.Name }}
  labels:
    {{- include "gamecloud.labels" . | nindent 4 }}
    release: prometheus
spec:
  selector:
    matchLabels:
      {{- include "gamecloud.selector" . | nindent 6 }}
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

Se actualiza el *release* para aplicar el nuevo recurso:

```bash
helm upgrade gamecloud-ranking ./charts/gamecloud-ranking/ -n gamecloud
```

Se puede comprobar que el ServiceMonitor fue creado y que los *endpoints* de la API aparece en estado UP al ir a **Status** y luego **Target Health** de Prometheus:

```bash
kubectl get servicemonitor -n gamecloud
```

### Logs con Loki y Alloy

Se instala Loki en modo monolítico (SingleBinary), con almacenamiento en el sistema de archivos y sin *multi-tenancy*. La configuración se encuentra en `observabilidad/values-loki.yaml`:

```yaml
deploymentMode: SingleBinary

loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  useTestSchema: true

singleBinary:
  replicas: 1
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0
```

Se instala Loki utilizando la versión de *chart* empleada en la práctica:

```bash
helm install loki grafana/loki -n observabilidad -f observabilidad/values-loki.yaml --version 7.5.0
```

Luego se instala Alloy con la configuración propia ubicada en `observabilidad/values-alloy.yaml`. Esta configuración descubre los *pods* del clúster, obtiene los metadatos de Kubernetes, agrega los *labels* `namespace`, `pod`, `container` y `app`, procesa los *logs* JSON y los envía a Loki:

```bash
helm install alloy grafana/alloy -n observabilidad -f observabilidad/values-alloy.yaml --version 1.14.2
```

Para verificar ambos despliegues:

```bash
kubectl get pods -n observabilidad
```

Desde Grafana, en **Explore**, se selecciona el *datasource* Loki. Para consultar los *logs* de la aplicación:

```logql
{namespace="gamecloud", app="gamecloud-ranking"}
```

Para filtrar los registros de error:

```logql
{namespace="gamecloud", app="gamecloud-ranking", level="error"}
```

### Dashboard de GameCloud

Desde Grafana se crea un *dashboard* y se agregan paneles utilizando el *datasource* Prometheus para las métricas y Loki para los *logs*. Las consultas utilizadas son las siguientes:

**Pedidos por Segundo (Separados por Rutas):**

```promql
sum by (ruta) (rate(http_requests_total[5m]))
```

**Latencia P95 (Separados por Rutas):**

```promql
histogram_quantile(
  0.95,
  sum by (le, ruta) (rate(http_request_duration_seconds_bucket[5m]))
)
```

**Pods Disponibles:**

```promql
sum by (pod) (
  kube_pod_status_ready{
    namespace="gamecloud",
    condition="true",
    pod=~"gamecloud-ranking-[^-]+-[^-]+"
  }
)
```

**Reinicios por Pod:**

```promql
sum by (pod) (
  kube_pod_container_status_restarts_total{
    namespace="gamecloud",
    pod=~"gamecloud-ranking-[^-]+-[^-]+"
  }
)
```

**Uso de CPU por Pod:**

```promql
sum by (pod) (
  rate(
    container_cpu_usage_seconds_total{
      namespace="gamecloud",
      pod=~"gamecloud-ranking-[^-]+-[^-]+",
      container!="", image!=""
    }[5m]
  )
)
```

**Uso de Memoria por Pod:**

```promql
sum by (pod) (
  container_memory_working_set_bytes{
    namespace="gamecloud",
    pod=~"gamecloud-ranking-[^-]+-[^-]+",
    container!="", image!=""
  }
)
```

**Uso de CPU por Pod Respecto al Límite:**

```promql
100 * sum by (pod) (
  rate(
    container_cpu_usage_seconds_total{
      namespace="gamecloud",
      pod=~"gamecloud-ranking-[^-]+-[^-]+",
      container!="", image!=""
    }[5m]
  )
) / sum by (pod) (
  kube_pod_container_resource_limits{
    namespace="gamecloud",
    pod=~"gamecloud-ranking-[^-]+-[^-]+",
    resource="cpu",
    unit="core"
  }
)
```

**Uso de Memoria por Pod Respecto al Límite:**

```promql
100 * sum by (pod) (
  container_memory_working_set_bytes{
    namespace="gamecloud",
    pod=~"gamecloud-ranking-[^-]+-[^-]+",
    container!="", image!=""
  }
) / sum by (pod) (
  kube_pod_container_resource_limits{
    namespace="gamecloud",
    pod=~"gamecloud-ranking-[^-]+-[^-]+",
    resource="memory",
    unit="byte"
  }
)
```

**Tasa de Errores 5XX:**

```promql
100 *
sum(rate(
  http_requests_total{status=~"5.."}[5m]
))
/
sum(rate(
  http_requests_total[5m]
))
```

**Errores de la API:**

```logql
{namespace="gamecloud", app="gamecloud-ranking", level="error"}
```

### Escenarios de Falla

Los *scripts* permiten reproducir los cuatro escenarios de falla. Se deben ejecutar desde el directorio donde se encuentran y de a uno por vez. Luego de observar cada escenario en los paneles de Grafana, se ejecuta `normal.sh` para restaurar el estado basal antes de continuar con el siguiente:

**Errores HTTP 500:**

```bash
bash 1_errores.sh
```

El *script* induce respuestas HTTP 500 en aproximadamente el 20% de las solicitudes. Se observa el aumento del porcentaje de errores 5XX y los registros correspondientes en Loki.

**Aumento artificial de latencia:**

```bash
bash 2_latencia.sh
```

El *script* agrega aproximadamente dos segundos al procesamiento de cada solicitud. Se observa el aumento del P95 y la disminución de los pedidos por segundo.

**CrashLoopBackOff:**

```bash
bash 3_crashloop.sh
```

El *script* despliega una configuración defectuosa que impide que los nuevos pods alcancen el estado Ready. Se observan los reinicios y la disponibilidad de las réplicas desde Grafana y se pueden consultar los eventos y *logs* de los *pods* con:

```bash
kubectl get pods -n gamecloud
```

```bash
kubectl describe pod <nombre-pod> -n gamecloud
```

```bash
kubectl logs <nombre-pod> -n gamecloud
```

**Puerto incorrecto en el Service:**

```bash
bash 4_puerto_service.sh
```

El *script* modifica el puerto de destino del Service, impidiendo que las solicitudes lleguen a la aplicación. Se observa la caída del *throughput* y se puede inspeccionar la configuración con:

```bash
kubectl get service gamecloud-ranking -n gamecloud -o yaml
```

```bash
kubectl get pod <nombre-pod> -n gamecloud -o yaml
```

**Restaurar el estado normal:**

```bash
bash normal.sh
```

Se debe ejecutar este último *script* después de cada escenario para volver a la configuración basal de la API.
