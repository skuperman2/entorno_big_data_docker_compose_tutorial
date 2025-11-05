# Entorno Big Data local con Docker Compose

**Objetivo:** Proveer un tutorial paso a paso para crear un entorno local reproducible para prácticas de Big Data (Hadoop + Spark, MongoDB, Cassandra, Kafka + Zookeeper, ELK) que puedas usar como material para tus estudiantes.

**Duración estimada de setup:** 30–60 minutos (dependiendo de la conexión y máquina)

---

## Contenido del documento

1. Requisitos
2. Estructura de carpetas
3. `docker-compose.yml` completo
4. Archivos de configuración adicionales (Logstash, Kibana dashboards - guía)
5. Scripts útiles (start / stop / init)
6. Datasets de ejemplo y cómo cargarlos
7. Comandos básicos de verificación y ejemplos de uso (HDFS, Spark, MongoDB, Cassandra, Kafka, ELK)
8. Conexión desde VSCode y Jupyter
9. Notas y problemas habituales

---

## 1) Requisitos

- Docker y Docker Compose instalados (Docker Desktop o Docker Engine + docker-compose).
- 8+ GB de RAM recomendados para ejecutar todos los servicios (puedes arrancar servicios parciales si tu máquina tiene menos recursos).
- VSCode (recomendado) y/o Jupyter Notebook / JupyterLab para desarrollo interactivo.

---

## 2) Estructura de carpetas recomendada

```
bigdata-environment/
├── docker-compose.yml
├── env/                      # variables de entorno si querés separarlas
├── logstash/
│   └── logstash.conf
├── kibana/
│   └── dashboards/           # opcional: json de dashboards exportados
├── datasets/
│   ├── web_logs/
│   │   └── access.log
│   ├── retail/
│   │   └── ventas.csv
│   └── tweets/
│       └── tweets.json
├── scripts/
│   ├── start.sh
│   ├── stop.sh
│   └── init-mongo.sh
└── jupyter/
    └── notebooks/            # notebooks ejemplo (PySpark, ML)
```

Crea esta estructura base antes de copiar los archivos.

---

## 3) `docker-compose.yml` (ejemplo completo)

> Nota: este `docker-compose.yml` usa imágenes ampliamente usadas en la comunidad. Son ejemplos; si preferís otras imágenes (Bitnami, Open Source), podés sustituirlas.

```yaml
version: '3.8'

services:

  # ----------------- HADOOP (NameNode + DataNode) -----------------
  namenode:
    image: bde2020/hadoop-namenode:2.0.0-hadoop2.7.4-java8
    container_name: namenode
    environment:
      - CLUSTER_NAME=bigdata
      - CORE_CONF_fs_defaultFS=hdfs://namenode:8020
    ports:
      - "9870:9870" # NameNode web UI
    volumes:
      - hadoop_namenode:/hadoop/dfs/name
    networks:
      - bigdata-net

  datanode:
    image: bde2020/hadoop-datanode:2.0.0-hadoop2.7.4-java8
    container_name: datanode
    environment:
      - CORE_CONF_fs_defaultFS=hdfs://namenode:8020
    depends_on:
      - namenode
    ports:
      - "9864:9864" # DataNode web UI
    volumes:
      - hadoop_datanode:/hadoop/dfs/data
    networks:
      - bigdata-net

  # ----------------- SPARK (master + worker) -----------------
  spark-master:
    image: bitnami/spark:3
    container_name: spark-master
    environment:
      - SPARK_MODE=master
      - ALLOW_PLAINTEXT_LISTENER=yes
    ports:
      - "8080:8080" # Spark master UI
      - "7077:7077" # Spark master (spark://)
    networks:
      - bigdata-net

  spark-worker:
    image: bitnami/spark:3
    container_name: spark-worker
    environment:
      - SPARK_MODE=worker
      - SPARK_MASTER_URL=spark://spark-master:7077
    depends_on:
      - spark-master
    ports:
      - "8081:8081" # Spark worker UI
    networks:
      - bigdata-net

  # ----------------- MONGODB -----------------
  mongo:
    image: mongo:6.0
    container_name: mongo
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db
    networks:
      - bigdata-net

  # ----------------- CASSANDRA -----------------
  cassandra:
    image: cassandra:4.0
    container_name: cassandra
    environment:
      - CASSANDRA_START_RPC=true
    ports:
      - "9042:9042"
    volumes:
      - cassandra_data:/var/lib/cassandra
    networks:
      - bigdata-net

  # ----------------- ZOOKEEPER & KAFKA -----------------
  zookeeper:
    image: confluentinc/cp-zookeeper:7.3.0
    container_name: zookeeper
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    ports:
      - "2181:2181"
    networks:
      - bigdata-net

  kafka:
    image: confluentinc/cp-kafka:7.3.0
    container_name: kafka
    depends_on:
      - zookeeper
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
    ports:
      - "9092:9092"
    networks:
      - bigdata-net

  # ----------------- ELASTIC (Elasticsearch, Logstash, Kibana) -----------------
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.11
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - es_data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
      - "9300:9300"
    networks:
      - bigdata-net

  logstash:
    image: docker.elastic.co/logstash/logstash:7.17.11
    container_name: logstash
    volumes:
      - ./logstash/logstash.conf:/usr/share/logstash/pipeline/logstash.conf:ro
    depends_on:
      - elasticsearch
    ports:
      - "5000:5000" # puerto para recibir logs (beats, tcp)
    networks:
      - bigdata-net

  kibana:
    image: docker.elastic.co/kibana/kibana:7.17.11
    container_name: kibana
    depends_on:
      - elasticsearch
    ports:
      - "5601:5601"
    networks:
      - bigdata-net

  # ----------------- JUPYTER (PySpark notebook) -----------------
  jupyter:
    image: jupyter/pyspark-notebook:latest
    container_name: jupyter
    environment:
      - JUPYTER_ENABLE_LAB=yes
    ports:
      - "8888:8888"
    volumes:
      - ./jupyter/notebooks:/home/jovyan/work
    depends_on:
      - spark-master
    networks:
      - bigdata-net

volumes:
  hadoop_namenode:
  hadoop_datanode:
  mongo_data:
  cassandra_data:
  es_data:

networks:
  bigdata-net:
    driver: bridge
```

> **Tip:** si tu máquina tiene menos recursos, levanta primero sólo MongoDB, Kafka y ELK para las prácticas de ingest/visualización y luego suma Hadoop/Spark cuando puedas.

---

## 4) Archivos de configuración adicionales

### `logstash/logstash.conf` (ejemplo para leer logs Apache)

```conf
input {
  tcp {
    port => 5000
    codec => plain
  }
}

filter {
  grok {
    match => { "message" => "%{COMBINEDAPACHELOG}" }
  }
  date {
    match => [ "timestamp" , "dd/MMM/yyyy:HH:mm:ss Z" ]
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "apache-logs-%{+YYYY.MM.dd}"
  }
  stdout { codec => rubydebug }
}
```

---

## 5) Scripts útiles

### `scripts/start.sh`

```bash
#!/usr/bin/env bash
set -e

echo "Arrancando stack..."
docker-compose up -d

echo "Esperar unos segundos a que los servicios inicien (NameNode, Elasticsearch, Kafka...)"

docker-compose ps
```

### `scripts/stop.sh`

```bash
#!/usr/bin/env bash
set -e

echo "Deteniendo stack..."
docker-compose down
```

### `scripts/init-mongo.sh` (opcional)

```bash
#!/usr/bin/env bash
# ejemplo: cargar datos de ventas en mongo

mongoimport --host mongo --db retail --collection ventas --type csv --headerline --file /datasets/retail/ventas.csv
```

> Recordá marcar estos scripts como ejecutables (`chmod +x scripts/*.sh`).

---

## 6) Datasets de ejemplo y cómo crearlos

Colocá los datasets dentro de `datasets/`.

### a) Logs web (Apache) — `datasets/web_logs/access.log`

Ejemplo de línea (Common/Combined Log Format):

```
127.0.0.1 - - [10/Oct/2023:13:55:36 -0300] "GET /index.html HTTP/1.1" 200 2326 "-" "Mozilla/5.0"
```

Podés generar logs sintéticos con un script simple (bash + `shuf`) o bajarlos de datasets públicos cuando tengas Internet.

### b) Retail / ventas (CSV) — `datasets/retail/ventas.csv`

Ejemplo de contenido (primeras 6 líneas):

```
order_id,date,customer_id,amount,product,category
1,2023-05-12,1001,59.99,camisa,ropa
2,2023-05-13,1002,249.00,smartphone,electronica
3,2023-05-14,1003,19.90,libro,literatura
```

### c) Tweets (JSON) — `datasets/tweets/tweets.json`

Ejemplo (formato JSON newline-delimited):

```
{"id":1, "user":"juan", "text":"Me encanta BigData! #bd", "created_at":"2023-08-01T12:00:00"}
{"id":2, "user":"ana", "text":"Probando pipeline #kafka", "created_at":"2023-08-01T12:01:00"}
```

---

## 7) Comandos básicos de verificación y ejemplos de uso

### HDFS (NameNode web UI: http://localhost:9870)

```bash
# listar el filesystem
docker exec -it namenode bash -lc "hdfs dfs -ls /"

# crear carpeta y copiar datos
docker exec -it namenode bash -lc "hdfs dfs -mkdir -p /user/demo && hdfs dfs -put /datasets/retail/ventas.csv /user/demo/"
```

### Spark (en Jupyter o submit)

- Abrir Jupyter: http://localhost:8888 (token en logs del contenedor jupyter)
- En notebook PySpark, configurar `spark.master` a `spark://spark-master:7077` y lanzar trabajos usando `pyspark` or `SparkSession`.

Ejemplo PySpark (notebook):

```python
from pyspark.sql import SparkSession
spark = SparkSession.builder.master("spark://spark-master:7077").appName("demo").getOrCreate()
df = spark.read.csv('/datasets/retail/ventas.csv', header=True, inferSchema=True)
df.groupBy('category').count().show()
```

> Nota: podés mapear la carpeta `datasets` dentro del contenedor jupyter si querés accesibilidad directa.

### MongoDB

```bash
# entrar a mongo shell
docker exec -it mongo mongo

# ver bases
show dbs
```

### Cassandra

```bash
# cqlsh
docker exec -it cassandra cqlsh

# crear keyspace
CREATE KEYSPACE IF NOT EXISTS demo WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'};
```

### Kafka

```bash
# crear topic
docker exec -it kafka kafka-topics --create --topic tweets --bootstrap-server kafka:9092 --partitions 1 --replication-factor 1

# producir (ejemplo)
docker exec -i kafka kafka-console-producer --topic tweets --bootstrap-server kafka:9092 <<< "{'id':1,'text':'hola'}"

# consumir
docker exec -it kafka kafka-console-consumer --topic tweets --bootstrap-server kafka:9092 --from-beginning --max-messages 10
```

### ELK (Kibana http://localhost:5601)

- Enviar logs a Logstash puerto 5000 (ej: `nc kafka 5000 < access.log`) o usar `filebeat` local para forwardear.
- Abrir Kibana y crear index patterns `apache-logs-*`.

---

## 8) Conexión desde VSCode y Jupyter

- VSCode: usar extension "Docker" y "Remote Containers" (si trabajás con devcontainer) para abrir el proyecto y lanzar terminales dentro de contenedores.
- Jupyter: abrir http://localhost:8888 y usar notebooks PySpark conectados al master.

Sugerencia: crear un `README.md` en la carpeta `jupyter/notebooks` con instrucciones paso a paso para levantar el kernel y ejemplos de notebooks.

---

## 9) Notas y problemas habituales

- **Memoria/CPU:** Si hay OutOfMemory en Elasticsearch o containers que no arrancan, revisá recursos de Docker Desktop y reduce cantidad de contenedores activos.
- **Puertos ocupados:** Algunos puertos (9200, 5601, 8888) pueden estar en uso. Cambialos si es necesario.
- **Imágenes/pulls:** Algunas imágenes son pesadas; la primera descarga puede tardar.
- **Persistencia de datos:** Las `volumes` en docker-compose preservan datos entre reinicios; para limpiar usar `docker-compose down -v`.

---

## 10) Actividad propuesta para los estudiantes (para la primera práctica)

1. Levantar solo MongoDB + Kafka + ELK.
2. Generar logs sintéticos y enviarlos a Logstash (puerto 5000).
3. Crear en Kibana un dashboard con: requests por minuto, top URLs, códigos de estado.
4. Levantar Hadoop/Spark y procesar el dataset `ventas.csv` -> agrupar por categoría y guardar resultados en MongoDB.

---

## ¿Querés que genere ahora:
- El archivo `docker-compose.yml` listo para copiar (te lo dejo en el documento),
- Un notebook PySpark de ejemplo para la práctica de ventas, y
- Un script para generar logs sintéticos para la práctica ELK?

Si querés, lo creo y lo agrego directamente en el mismo repositorio de archivos (en el documento) para que lo copies.

---

*Fin del documento.*

