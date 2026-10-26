# Supervision avec la stack ELK

Elasticsearch, Kibana, Logstash, Filebeat et Metricbeat, avec TLS et authentification, lancés dans un projet Compose distinct de l'application (`compose.elk.yml`, nom `microcrm-elk`).

## Démarrage

Prérequis :
- `sudo sysctl -w vm.max_map_count=262144` ;
- `cp .env.elk.example .env.elk`, puis changer les mots de passe et générer `ENCRYPTION_KEY` (`openssl rand -hex 32`). `.env.elk` n'est pas versionné.

```bash
./elk.sh up      # sudo docker compose --env-file .env.elk -f compose.elk.yml up -d
./elk.sh down    # arrêt ; ajouter -v à la commande Compose pour supprimer les données
```

Le conteneur `setup` génère les certificats et le mot de passe `kibana_system`, puis s'arrête (normal). Kibana : http://localhost:5601 (utilisateur `elastic`).

## Ce qui est collecté

```
 microcrm-back-1  (Spring, JSON ECS) ─┐ stdout            ┌───────────┐
 microcrm-front-1 (Caddy, JSON)     ──┴──▶ Filebeat ─────▶│           │
 back :8080/actuator/prometheus ────┐                     │ Elastic-  │◀── Kibana :5601
 docker.sock (CPU, mémoire)     ────┴──▶ Metricbeat ─────▶│ search    │
 elk/logstash_ingest_data/      ───────▶ Logstash ───────▶│           │
                                                          └───────────┘
```

| Source | Collecteur | Index | Contenu |
|--------|------------|-------|---------|
| Logs du back | Filebeat (input `container`) | `filebeat-*` | JSON ECS (`logging.structured.format.console=ecs`) : `log.level`, `log.logger`, `message`, `error.*` ; en profil `dev`, une ligne par requête HTTP |
| Logs d'accès Caddy (front) | Filebeat | `filebeat-*` | `request.uri`, `status`, `duration` |
| Conteneurs | Metricbeat, module `docker` | `metricbeat-*` | CPU, mémoire, réseau, healthchecks |
| Métriques du back | Metricbeat, module `prometheus` | `metricbeat-*` | JVM, `http_server_requests_*`, pool JDBC (profil `dev` uniquement) |
| Fichiers déposés | Logstash | `logstash-*` | Contenu de `elk/logstash_ingest_data/` |

Filebeat ne garde que les conteneurs `microcrm-back-*` et `microcrm-front-*`. Dans Kibana : data view `filebeat-*`, filtre `container.name : "microcrm-back-1"`.

Limites : les appels API du navigateur vont directement au back (`http://localhost:8080`), sans passer par Caddy ; Caddy ne journalise que le chargement de la SPA. Les erreurs JavaScript du navigateur ne sont pas collectées.

## Sécurité et dépannage

- TLS dans toute la stack, mots de passe dans `.env.elk`. Les beats utilisent le compte `elastic` (acceptable en dev, rôles dédiés en production). `docker.sock` et les logs Docker sont montés en lecture seule.
- Aucun log dans Kibana : vérifier que Filebeat est `Up` (`docker ps`), générer du trafic (`curl localhost:8080/api/organizations`), puis `docker logs microcrm-elk-filebeat01-1`.
- Fedora : SELinux peut bloquer les montages de Filebeat (`security_opt: ["label=disable"]`) et firewalld l'accès de Metricbeat à `host.docker.internal:8080`.

L'indicateur suivi dans ELK (fréquence des erreurs) est décrit dans [04](04-dora-kpi.md).
