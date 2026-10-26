# Supervision avec ELK

Objectif : centraliser les logs de MicroCRM dans la stack Elastic (Elasticsearch, Logstash, Kibana + Beats) et disposer d'un **tableau de bord Kibana**. Celui-ci affiche les logs applicatifs et des visualisations simples : **volume de logs**, **erreurs** et **fréquence des événements**.

Fichiers : `compose.elk.yml` (stack ELK), `elk.sh` (démarrage et arrêt), `elk/filebeat.yml`, `elk/metricbeat.yml`, `elk/logstash.conf`, `.env.elk.example`.

## Architecture

```
 microcrm-back-1  (Spring, logs JSON ECS) ─┐ stdout              ┌───────────────┐
 microcrm-front-1 (Caddy, logs JSON)      ─┴──▶ Filebeat ───────▶│               │
 back :8080/actuator/prometheus ──────────┐                      │ Elasticsearch │◀── Kibana :5601
 docker.sock (CPU, mémoire, santé)  ──────┴──▶ Metricbeat ──────▶│   (es01)      │    (tableau de bord)
 elk/logstash_ingest_data/*  ─────────────────▶ Logstash ───────▶│               │
                                                                 └───────────────┘
```

La stack ELK est un **projet Compose distinct** de l'application (`microcrm-elk`). On peut ainsi superviser l'application sans la modifier, et démarrer ou arrêter la supervision indépendamment.

| Source | Collecteur | Index | Contenu utile |
|--------|------------|-------|---------------|
| Logs du back (Spring Boot) | Filebeat, input `container` | `filebeat-*` | JSON ECS : `log.level`, `log.logger`, `message`, `error.type`, `error.message`, `service.name` |
| Logs d'accès du front (Caddy) | Filebeat | `filebeat-*` | `request.uri`, `status`, `duration` |
| Conteneurs | Metricbeat, module `docker` | `metricbeat-*` | CPU, mémoire, réseau, healthchecks |
| Métriques du back | Metricbeat, module `prometheus` | `metricbeat-*` | JVM, requêtes HTTP, pool JDBC |
| Fichiers déposés | Logstash | `logstash-*` | Contenu de `elk/logstash_ingest_data/` |

## Choix techniques

| Choix | Justification |
|-------|---------------|
| **Logs JSON au format ECS** (encodeur `logback-ecs-encoder`) | Chaque log arrive déjà structuré (niveau, logger, exception) : aucun parsing à écrire, et les champs sont directement filtrables dans Kibana |
| **Filebeat lit les logs des conteneurs** (`/var/lib/docker/containers`) | L'application écrit simplement sur la sortie standard, sans dépendance vers ELK dans son code (principe des *12-factor apps*) |
| **Filtre sur `microcrm-(back\|front)-*`** | On ne collecte que l'application, pas les conteneurs de la stack ELK elle-même |
| **Metricbeat + Actuator/Prometheus** | Métriques techniques (JVM, HTTP, conteneurs) en complément des logs |
| **TLS et authentification** (certificats générés par le conteneur `setup`) | Bonnes pratiques de sécurité, même en local. Les mots de passe sont dans `.env.elk`, non versionné |
| **Projet Compose séparé** | Cycle de vie indépendant de l'application ; la stack ELK est lourde (environ 3 Go de RAM) |

## Démarrage

**Prérequis**
1. Copier la configuration et changer les secrets :
   ```shell
   cp .env.elk.example .env.elk          # puis modifier ELASTIC_PASSWORD, KIBANA_PASSWORD
   openssl rand -hex 32                  # valeur pour ENCRYPTION_KEY
   ```
2. Augmenter `vm.max_map_count`, une exigence d'Elasticsearch :
   - Linux : `sudo sysctl -w vm.max_map_count=262144`
   - Docker Desktop (Windows) : `wsl -d docker-desktop sysctl -w vm.max_map_count=262144`

**Lancement**
```shell
docker compose up -d --build       # 1. l'application (conteneurs microcrm-back-1 / microcrm-front-1)
./elk.sh up                        # 2. la stack ELK (Linux)
# Windows : docker compose --env-file .env.elk -f compose.elk.yml up -d
```

Le conteneur `setup` génère les certificats et le mot de passe de `kibana_system`, puis s'arrête : c'est normal. Kibana est disponible après 1 à 2 minutes sur **http://localhost:5601** (utilisateur `elastic`, mot de passe de `.env.elk`).

Au premier démarrage, Filebeat installe ses dashboards par défaut dans Kibana (`setup.dashboards.enabled`) **avant** de collecter. Les logs apparaissent donc au bout d'environ 3 minutes, historique compris.

**Arrêt** : `./elk.sh down`. Ajouter `-v` à la commande Compose pour supprimer aussi les données.

## Générer des logs

```shell
# Trafic normal (une ligne de log par requête HTTP en profil dev)
for i in $(seq 1 20); do curl -s localhost:8080/persons > /dev/null; curl -sk https://localhost/ > /dev/null; done

# Avertissement : identifiant invalide (WARN avec error.type)
curl -s localhost:8080/persons/abc

# Erreur : suppression d'une organisation liée à des personnes (500, log ERROR)
curl -s -X DELETE localhost:8080/organizations/1
```

## Créer le tableau de bord dans Kibana

### 1. Data view
*Stack Management > Data Views > Create data view* :
- **Name** : `MicroCRM logs`
- **Index pattern** : `filebeat-*`
- **Timestamp field** : `@timestamp`

### 2. Recherche « Logs applicatifs » (Discover)
*Analytics > Discover*, data view `MicroCRM logs` :
- Requête KQL : `container.name : microcrm-*`
- Colonnes : `container.name`, `log.level`, `log.logger`, `message`
- *Save* → **Logs applicatifs**

### 3. Visualisations (Lens)
*Analytics > Visualize Library > Create visualization > Lens*, data view `MicroCRM logs` :

| Visualisation | Type | Configuration | Ce qu'elle montre |
|---------------|------|---------------|-------------------|
| **Volume de logs** | Barres verticales empilées | Axe X : `@timestamp` (date histogram) ; Axe Y : *Count* ; Ventilation : `container.name` | Nombre de lignes de log dans le temps, par service |
| **Erreurs dans le temps** | Barres verticales | Filtre KQL : `log.level : "ERROR" or log.level : "WARN"` ; Axe X : `@timestamp` ; Axe Y : *Count* ; Ventilation : `log.level` | Apparition des avertissements et des erreurs |
| **Nombre d'erreurs** | Metric | Filtre KQL : `log.level : "ERROR"` ; *Count* | Total des erreurs sur la période, lisible d'un coup d'œil |
| **Répartition par niveau** | Donut | *Slice by* : `log.level` (top 5) ; *Count* | Part de `INFO`, `DEBUG`, `WARN` et `ERROR` |
| **Fréquence des événements** | Barres horizontales | *Vertical axis* : `log.logger` (top 10) ; *Count* | Composants qui produisent le plus d'événements |
| **Requêtes front par statut HTTP** (optionnel) | Barres verticales | Filtre KQL : `container.name : microcrm-front-*` ; Axe X : `@timestamp` ; Ventilation : `status` | Trafic et erreurs HTTP du serveur web |

Enregistrer chaque visualisation dans la bibliothèque (*Save and add to library*).

### 4. Tableau de bord
*Analytics > Dashboards > Create dashboard* :
1. *Add from library* : ajouter les visualisations et la recherche **Logs applicatifs** (en bas, pleine largeur).
2. Plage de temps : **Last 15 minutes**, rafraîchissement automatique : **10 seconds**.
3. *Save* → **MicroCRM – Supervision**. Cocher *Store time with dashboard*.

Disposition conseillée :

```
┌──────────────────┬──────────────────────────────────────────┐
│ Nombre d'erreurs │ Volume de logs (par service)             │
├──────────────────┼──────────────────────────────────────────┤
│ Répartition      │ Erreurs dans le temps (WARN / ERROR)     │
│ par niveau       ├──────────────────────────────────────────┤
│                  │ Fréquence des événements (top loggers)   │
├──────────────────┴──────────────────────────────────────────┤
│ Logs applicatifs (recherche Discover)                       │
└─────────────────────────────────────────────────────────────┘
```

### 5. Versionner le tableau de bord (export / import)

Le tableau de bord, ses visualisations, la recherche « Logs applicatifs » et la data view sont des **saved objects** Kibana, stockés dans Elasticsearch. Un `./elk.sh down -v` ou une nouvelle machine les fait disparaître. On les exporte donc dans un fichier **`.ndjson`** (un objet JSON par ligne), versionné dans le dépôt :

```
elk/kibana/dashboard-microcrm.ndjson
```

#### Export depuis l'interface
1. *Stack Management > Saved Objects*.
2. Rechercher `MicroCRM`, puis cocher le dashboard **MicroCRM – Supervision**.
3. *Export* : laisser **Include related objects** activé. Les visualisations, la recherche et la data view sont alors incluses ; sans elles, le dashboard importé serait vide.
4. Renommer le fichier téléchargé (`export.ndjson`) en `elk/kibana/dashboard-microcrm.ndjson`, puis le commiter.

#### Import depuis l'interface
1. *Stack Management > Saved Objects > Import*.
2. Sélectionner `elk/kibana/dashboard-microcrm.ndjson`.
3. Option **Check for existing objects** : choisir *Automatically overwrite conflicts* pour mettre à jour une version déjà présente.
4. Ouvrir *Analytics > Dashboards > MicroCRM – Supervision*.

#### Export et import en ligne de commande (API Kibana)
Utile pour automatiser, ou pour éviter les clics. Kibana écoute en HTTP sur le port 5601. Le compte et le mot de passe sont ceux de `.env.elk`, et l'en-tête `kbn-xsrf` est obligatoire.

```shell
export ELASTIC_PASSWORD=...        # valeur de .env.elk
KIBANA=http://localhost:5601

# 1. Retrouver l'identifiant du dashboard
curl -s -u "elastic:$ELASTIC_PASSWORD" \
  "$KIBANA/api/saved_objects/_find?type=dashboard&search_fields=title&search=MicroCRM*" \
  | grep -o '"id":"[^"]*"' | head -1

# 2. Exporter le dashboard et tous les objets dont il dépend
curl -s -u "elastic:$ELASTIC_PASSWORD" -X POST "$KIBANA/api/saved_objects/_export" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{"objects":[{"type":"dashboard","id":"<ID>"}],"includeReferencesDeep":true}' \
  -o elk/kibana/dashboard-microcrm.ndjson

# 3. Importer (écrase les objets existants de même identifiant)
curl -s -u "elastic:$ELASTIC_PASSWORD" -X POST "$KIBANA/api/saved_objects/_import?overwrite=true" \
  -H "kbn-xsrf: true" --form file=@elk/kibana/dashboard-microcrm.ndjson
```

L'import renvoie `"success":true` et le nombre d'objets importés (`successCount`). En cas d'échec, le détail se trouve dans `errors`.

#### Points d'attention
- **Les identifiants sont conservés** : réimporter le fichier met à jour le même dashboard au lieu d'en créer un doublon.
- **Compatibilité des versions** : un export s'importe dans la même version de Kibana ou dans une version plus récente, jamais plus ancienne. La version est fixée par `STACK_VERSION` dans `.env.elk`.
- **Les données ne sont pas exportées** : seuls les objets de configuration le sont. Les logs restent dans Elasticsearch, et le dashboard importé se remplit dès que Filebeat envoie de nouveaux logs.
- **Pas de secret dans le fichier** : un export de dashboard ne contient ni mot de passe ni clé. On peut le commiter sans risque, mais il vaut mieux le relire avant.
- **Après chaque modification** du dashboard dans Kibana, refaire l'export et commiter le fichier, pour que la version du dépôt reste la référence.

## Lire le tableau de bord

- **Volume de logs** : un pic correspond à un afflux de requêtes. Une chute à zéro signale un service arrêté ou une collecte interrompue.
- **Erreurs dans le temps** et **Nombre d'erreurs** : toute barre `ERROR` mérite une analyse. Un clic sur la barre filtre la recherche **Logs applicatifs**, qui affiche alors le message et `error.type`.
- **Fréquence des événements** : repérer un composant anormalement bavard, par exemple une boucle de logs ou des requêtes répétées.

## Dépannage

| Symptôme | Vérification |
|----------|--------------|
| Aucun log dans Kibana | Attendre la fin de l'installation des dashboards Filebeat (environ 3 min). Vérifier `docker logs microcrm-elk-filebeat01-1` : chercher « Harvester started » |
| Logs du front ou du back absents | Les conteneurs doivent s'appeler `microcrm-back-*` et `microcrm-front-*`, ce qui correspond au nom de projet `microcrm` dans `compose.yml` |
| Elasticsearch redémarre en boucle | `vm.max_map_count` est trop bas (voir les prérequis) ou la mémoire est insuffisante (`ES_MEM_LIMIT`) |
| Pas de métriques Prometheus | Le back doit être joignable sur `host.docker.internal:8080` (pare-feu) |

## Limites

- Les appels API du navigateur vont directement au back (`localhost:8080`). Caddy ne journalise que le chargement du front.
- Les erreurs JavaScript côté navigateur ne sont pas collectées.
- Les Beats utilisent le compte `elastic` : c'est acceptable en local, mais il faudra des rôles dédiés en production.
- Les montages de `docker.sock` et des logs Docker (en lecture seule) supposent un hôte Docker Linux ou Docker Desktop.
