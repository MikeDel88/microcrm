# Conteneurisation et orchestration

Objectif : lancer MicroCRM (front + back) avec une seule commande, et justifier les choix techniques. Ce document applique les principes de [06-conteneurisation-deploiement.md](06-conteneurisation-deploiement.md).

## Lancer l'application

```shell
docker compose up --build        # construit les images et démarre front + back
docker compose up --build -d     # idem, en arrière-plan
docker compose ps                # état des services (healthy attendu)
docker compose down              # arrêt et suppression des conteneurs
```

| Service | URL | Rôle |
|---------|-----|------|
| `front` | https://localhost (http://localhost redirige vers HTTPS) | Application Angular servie par Caddy |
| `back`  | http://localhost:8080 | API REST Spring Boot (`/persons`, `/organizations`, `/actuator/health`) |

Profil Spring : `dev` par défaut. Pour un autre profil : `SPRING_PROFILES_ACTIVE=prod docker compose up --build`.

## Fichiers

| Fichier | Rôle |
|---------|------|
| `Dockerfile` | Build multi-stage : `front-build` et `back-build` compilent, `front` et `back` exécutent |
| `compose.yml` | Orchestration des deux services (build, ports, configuration, santé, ordre de démarrage) |
| `.dockerignore` | Exclut du contexte de build ce qui est inutile (git, docs, `node_modules`, `build/`…) |
| `misc/docker/Caddyfile` | Configuration du serveur web du front |
| `.gitattributes` | Force les fins de ligne LF pour `gradlew` et les scripts `.sh`, exécutés sous Linux |

## Choix techniques

| Choix | Justification |
|-------|---------------|
| **Dockerfile multi-stage unique** à la racine du monorepo | Un seul contexte de build pour les deux applications. Les images finales ne contiennent que le résultat du build, sans Node, Gradle ni sources : elles sont plus légères et exposent moins de surface d'attaque |
| **Images de base figées** (`node:20-alpine`, `gradle:8.7.0-jdk17-alpine`, `caddy:2.11.7-alpine`, `eclipse-temurin:17-jre-alpine`) | Builds reproductibles. Java 17 et Gradle 8.7 sont les versions du projet et de la CI, l'exécution utilise un JRE seul et les images Alpine restent légères |
| **Cache des dépendances** : copie des manifestes, `npm ci` et `gradlew dependencies` avant la copie des sources | Une modification du code ne retélécharge pas les dépendances, ce qui accélère les rebuilds |
| **Tests exclus du build d'image** (`bootJar -x test`) | Les tests sont déjà exécutés par la CI ; inutile de les relancer à chaque build d'image |
| **Utilisateur non-root** (`app`) dans les deux images | Bonne pratique de sécurité (voir [05-plan-securite.md](05-plan-securite.md)) |
| **Caddy** pour servir le front | HTTPS automatique avec un certificat interne, redirection HTTP → HTTPS, compression gzip, logs JSON. `try_files` renvoie vers `index.html`, ce qui permet le routage Angular |
| **Un service par conteneur** (`front`, `back`) | Remplace l'image `standalone` d'origine (deux processus via supervisord). Chaque service se construit, se met à l'échelle et se supervise séparément |
| **Healthchecks** : `/actuator/health` pour le back, requête HTTPS pour le front | Docker connaît l'état réel de chaque service, et pas seulement « conteneur démarré » |
| **`depends_on: condition: service_healthy`** | Le front ne démarre que lorsque l'API répond |
| **Profil Spring par variable d'environnement** | La même image sert dans tous les environnements, seule la configuration change (*build once, deploy many*) |
| **`restart: unless-stopped`** | Redémarrage automatique en cas de crash, sauf arrêt volontaire |
| **Nom de projet fixe** (`name: microcrm`) | Noms de conteneurs et d'images stables (`microcrm-back`, `microcrm-front`), quel que soit le dossier |
| **Nom `compose.yml`** | Convention par défaut de Docker Compose v2 (`docker-compose.yml` reste reconnu) |

## Préparation du déploiement

- Les images `front` et `back` sont indépendantes et prêtes à être publiées dans un registre (GHCR), avec des tags immuables : version SemVer ou SHA du commit.
- `compose.release.yml` surcharge `compose.yml` : il tire les images publiées au tag voulu au lieu de les construire, et force le profil `prod`.

  ```shell
  TAG=1.0.0 docker compose -f compose.yml -f compose.release.yml up -d
  ```
- Le retour arrière (*rollback*) consiste à relancer la même commande avec le tag précédent.

## Limites connues

- **URL de l'API fixée au build du front** (`http://localhost:8080`) : l'application fonctionne en local. Pour un autre hôte, l'URL devra être injectée à l'exécution.
- **Base HSQLDB en mémoire** : les données sont perdues à chaque redémarrage du back. Une vraie base avec volume persistant sera nécessaire en production.
- **Certificat HTTPS interne** (auto-signé) : le navigateur affiche un avertissement en local.
