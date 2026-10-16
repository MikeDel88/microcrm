# 07 - Supervision avec la stack ELK

Stack Elasticsearch + Kibana + Logstash + Metricbeat + Filebeat (TLS et authentification activés), inspirée de l'article Elastic « Getting started with the Elastic Stack and Docker Compose ».

## Prérequis
- `sudo sysctl -w vm.max_map_count=262144`
- `cp .env.elk.example .env.elk`, puis changer les mots de passe et générer `ENCRYPTION_KEY` (`openssl rand -hex 32`).

## Démarrage
```bash
docker compose --env-file .env.elk -f compose.elk.yml up -d
```
Le conteneur `setup` génère les certificats et le mot de passe `kibana_system`, puis s'arrête (comportement normal).

## Vérification
- Kibana : http://localhost:5601 (utilisateur `elastic`).
- Elasticsearch :
  ```bash
  docker cp $(docker compose -f compose.elk.yml ps -q es01):/usr/share/elasticsearch/config/certs/ca/ca.crt /tmp/ca.crt
  curl --cacert /tmp/ca.crt -u elastic:$ELASTIC_PASSWORD https://localhost:9200
  ```
- Les logs des conteneurs (Filebeat, autodiscover Docker) et leurs métriques (Metricbeat) apparaissent dans Kibana (Discover, Stack Monitoring).
- Fichiers `.log` déposés dans `elk/filebeat_ingest_data/` (Filebeat) ou fichiers dans `elk/logstash_ingest_data/` (Logstash, index `logstash-*`).

## Arrêt
`docker compose --env-file .env.elk -f compose.elk.yml down` (`-v` pour supprimer les données).
