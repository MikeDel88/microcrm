# 07 - Supervision avec la stack ELK

Stack Elasticsearch + Kibana + Logstash + Metricbeat + Filebeat (TLS et authentification activés), inspirée de l'article Elastic « Getting started with the Elastic Stack and Docker Compose ».

## Prérequis
- `sudo sysctl -w vm.max_map_count=262144`
- `cp .env.elk.example .env.elk`, puis changer les mots de passe et générer `ENCRYPTION_KEY` (`openssl rand -hex 32`).

## Démarrage
```bash
docker compose --env-file .env.elk -f compose.elk.yml up -d
```
Le conteneur `setup` génère les certificats et le mot de passe `kibana_system`, puis s'arrête (comportement normal). La stack ELK est un projet Compose distinct (`name: microcrm-elk`) de l'application (`microcrm`).

## Architecture

```
 HÔTE (Docker)
 ┌──────────────────────────┐
 │ microcrm-back-1 (Spring) │─ stdout JSON (ECS) ─┐
 │ microcrm-front-1 (Caddy) │─ stdout JSON ───────┤  /var/lib/docker/containers/*/*-json.log
 └──────────────────────────┘                     ▼
        │ :8080/actuator/prometheus         ┌─────────────┐  HTTPS + auth   ┌───────────────┐   ┌────────┐
        │ (profil dev)                      │  Filebeat   │ ───────────────▶│ Elasticsearch │◀──│ Kibana │ :5601
        └─ host.docker.internal ─▶ ┌──────────────┐       └─────────────┘   │   es01:9200   │   └────────┘
          docker.sock (CPU/mém.) ─▶│  Metricbeat  │ ─────────────────────▶ │               │
                                   └──────────────┘                         │               │
          elk/logstash_ingest_data ─▶ Logstash ───────────────────────────▶ └───────────────┘
```

| Service | Rôle |
|---|---|
| `setup` | Génère la CA et les certificats (volume `certs`), fixe le mot de passe `kibana_system`, puis s'arrête |
| `es01` | Elasticsearch single-node, TLS HTTP et transport, sécurité activée (port `ES_PORT`) |
| `kibana` | Discover, dashboards (port `KIBANA_PORT`) |
| `filebeat01` | Collecte des logs des conteneurs ; attend que `es01` et `kibana` soient healthy (chargement des dashboards au démarrage) |
| `metricbeat01` | Métriques Docker, métriques du back, monitoring de la stack |
| `logstash01` | Indexe les fichiers déposés dans `elk/logstash_ingest_data/` (index `logstash-*`) |

Configuration : `compose.elk.yml`, `.env.elk` (modèle `.env.elk.example`), `elk/filebeat.yml`, `elk/metricbeat.yml`, `elk/logstash.conf`.

## Chemin des logs

1. **Back** : `logging.structured.format.console=ecs` (`application.properties`) produit un JSON ECS par ligne sur stdout (`@timestamp`, `log.level`, `log.logger`, `message`, `error.*`). En profil dev : niveau DEBUG sur le package applicatif, SQL Hibernate, et une ligne par requête HTTP (`DispatcherServlet`).
2. **Front** : le navigateur n'envoie rien à ELK. Seul Caddy (`misc/docker/Caddyfile`) écrit des logs d'accès JSON sur stdout (`request.uri`, `status`, `duration`), dans un schéma différent d'ECS.
3. **Docker** : le pilote `json-file` écrit stdout dans `/var/lib/docker/containers/<id>/<id>-json.log`.
4. **Filebeat** (`elk/filebeat.yml`, input `container`) : `add_docker_metadata` ajoute `container.name`, `decode_json_fields` transforme le JSON du message en champs, `drop_event` ne garde que les conteneurs `microcrm-back-*` et `microcrm-front-*`. Sortie : `filebeat-*` dans Elasticsearch.
5. **Kibana** : data view `filebeat-*`, filtre `container.name : "microcrm-back-1"` ou `"microcrm-front-1"`.

Schémas : back = `log.level`, `log.logger` ; Caddy = `level`, `msg`, `request.*`, `status`, `duration`.

## Chemin des métriques (`elk/metricbeat.yml`)
- Module `docker` (10 s, via `docker.sock`) : CPU, mémoire, réseau, disque, healthcheck de chaque conteneur.
- Module `prometheus` : le back expose `/actuator/prometheus` (profil dev uniquement) ; Metricbeat l'interroge sur `host.docker.internal:8080` (JVM, `http_server_requests_*`, pool JDBC).
- Modules `elasticsearch` et `kibana` : monitoring de la stack. Sortie : `metricbeat-*`.

## Ce qui génère (ou non) des logs
- Appels API du navigateur : ils partent **directement vers `http://localhost:8080`** (`front/src/environments/environment.ts`), sans passer par Caddy. Ils sont visibles dans les logs du **back**.
- Caddy ne journalise que ce qu'il sert : `index.html` et les assets au chargement ou rechargement (F5). L'application Angular étant une SPA, naviguer d'une page à l'autre ne fait aucune requête vers Caddy.
- Les erreurs JavaScript du navigateur ne sont pas collectées (pas de RUM / APM).
- Les métriques applicatives du back ne sont exposées qu'en profil dev.

## Vérification
- Kibana : http://localhost:5601 (utilisateur `elastic`), data views `filebeat-*` et `metricbeat-*`.
- Elasticsearch :
  ```bash
  docker cp $(docker compose -f compose.elk.yml ps -q es01):/usr/share/elasticsearch/config/certs/ca/ca.crt /tmp/ca.crt
  curl --cacert /tmp/ca.crt -u elastic:$ELASTIC_PASSWORD https://localhost:9200
  ```
- Si Kibana n'affiche aucun log : `docker ps` (Filebeat doit être `Up`), `docker logs microcrm-back-1` après un `curl localhost:8080/api/organizations`, puis `docker logs microcrm-elk-filebeat01-1`.
- Fichiers `.log` déposés dans `elk/filebeat_ingest_data/` (Filebeat) ou fichiers dans `elk/logstash_ingest_data/` (Logstash, index `logstash-*`).

## Sécurité
TLS dans toute la stack, mots de passe dans `.env.elk` (non versionné). Les beats utilisent le compte `elastic` (acceptable en dev, à remplacer par des rôles dédiés en production). `docker.sock` et `/var/lib/docker/containers` sont montés en lecture seule.

## Particularités Fedora
`vm.max_map_count=262144` est requis ; SELinux peut bloquer les montages de Filebeat (`security_opt: ["label=disable"]`) et firewalld l'accès de Metricbeat à `host.docker.internal:8080`.

## Arrêt
`docker compose --env-file .env.elk -f compose.elk.yml down` (`-v` pour supprimer les données).
