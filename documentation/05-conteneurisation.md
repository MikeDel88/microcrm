# Conteneurisation

## 1. Dockerfile (racine, contexte = racine)

**État initial** : `node` et `gradle:jdk17` non épinglés, trois cibles d'exécution sur `alpine:3.19` (`front`, `back`, `standalone` avec supervisord), Caddy et `openjdk21-jre-headless` installés par `apk`, exécution en root, `EXPOSE 4200` sur le back, `./gradlew build` (tests relancés), JAR nommé `microcrm-0.0.1-SNAPSHOT.jar`, aucun `HEALTHCHECK`, `.dockerignore` minimal (5 lignes : `back/.gradle`, `back/build`, `front/dist`, `front/node_modules`, `front/.angular`). **Actuel** :

| Étape | Image | Rôle |
|-------|-------|------|
| `front-build` | `node:20-alpine` | `npm ci`, `npm run build` |
| `back-build` | `gradle:8.14.5-jdk17-alpine` | `./gradlew bootJar -x test` → `microcrm.jar` |
| `front` (cible) | `caddy:2.11.7-alpine` | Sert le build Angular, utilisateur `app` |
| `back` (cible) | `eclipse-temurin:17-jre-alpine` | `java -jar microcrm.jar`, utilisateur `app`, port 8080 |

- Les tests ne sont pas rejoués dans l'image (validés en CI).
- `.dockerignore` limite le contexte à `front/`, `back/` et `misc/docker/Caddyfile` (pas de `node_modules`, `build`, `.git`, documentation).
- Le nom du JAR est fixe (`archiveFileName = 'microcrm.jar'`) ; la version vient du tag d'image.

## 2. Suppression de la cible `standalone`

**Ce qu'elle était** (premier commit `323c2e1`) : une troisième cible sur `alpine:3.19` qui recopiait les systèmes de fichiers des cibles `front` et `back` et lançait Caddy et Java ensemble avec **supervisord** (`misc/docker/supervisor.ini`). Une seule image, un seul `docker run`.

**Supprimée** au commit `86e3e9b` (optimisation du `Dockerfile`), avec `supervisor.ini` et la section « Tout en un » du README.

| Raison | Détail |
|--------|--------|
| Un seul processus surveillé par Docker | Seul supervisord est suivi : si Caddy ou Java plantait, le conteneur restait « vivant » |
| Logs et redémarrages mélangés | Les deux services partageaient la sortie et le cycle de vie du conteneur |
| Pas de mise à jour séparée | Un changement du front reconstruisait et redéployait aussi le back, et inversement |
| Image plus lourde à scanner | Deux piles (Caddy, JRE) plus supervisord dans la même image : plus de paquets, plus de CVE |
| Exécution en root | Elle empêchait de passer en utilisateur non-root |

**Remplacement** : deux cibles `front` et `back`, lancées par Docker Compose (`compose.yml`), une image publiée par service.

**Contrepartie assumée** : deux images à publier et à scanner (matrice dans `cd.yml`), et Compose pour lancer l'ensemble.

**Alternative non retenue** : une image unique où Spring Boot sert lui-même le front (build Angular copié dans les ressources statiques du JAR). Elle supprimerait Caddy et rendrait l'URL de l'API relative, mais perdrait le HTTPS automatique de Caddy et l'indépendance front/back.

## 3. Healthchecks

| Cible | Commande | Délai de démarrage |
|-------|----------|--------------------|
| `back` | `wget -q -O /dev/null http://localhost:8080/organizations` | 30 s |
| `front` | `nc -z localhost 80` | 10 s |

`curl` n'existe pas sur Alpine (BusyBox : `wget`, `nc`). Le front est testé par `nc` car `wget` suivrait la redirection HTTP→HTTPS vers un certificat auto-signé. `compose.test.yml` redéfinit le healthcheck du back pour `--wait`.

## 4. Caddy (`misc/docker/Caddyfile`)

Bloc `*` : racine `/app/front`, compression gzip, `try_files {path} /index.html` (routes Angular), `file_server`. Sans nom de domaine, Caddy sert en HTTPS avec un certificat auto-signé et redirige le port 80. Il ne fait pas office de proxy vers le back.

## 5. Fichiers Compose

| Fichier | Rôle |
|---------|------|
| `compose.yml` | Services `back` (8080) et `front` (80, 443), `build:` depuis le `Dockerfile`, **sans `image:`** (la CI construit ainsi l'image depuis le Dockerfile) |
| `compose.dev.yml` | Profil Spring `dev` |
| `compose.test.yml` | Profil `test`, logs réduits (variables d'environnement), healthcheck du back |
| `compose.release.yml` | Exécute les images GHCR : `ghcr.io/mikedel88/microcrm-{back,front}:${TAG}`, `pull_policy: always`, profil `prod` forcé (`RELEASE_PROFILE` pour le changer) |

## 6. Profils Spring

| Profil | Fichier | Contenu | Dans le JAR |
|--------|---------|---------|-------------|
| `dev` | `src/main/resources/application-dev.properties` | SQL et logs DEBUG | Oui |
| `prod` | `src/main/resources/application-prod.properties` | Logs INFO, SQL masqué | Oui |
| `test` | `src/test/resources/application-test.properties` | Utilisé par `./gradlew test` | **Non** : en Compose, ses réglages passent par `compose.test.yml` |

La base reste HSQLDB en mémoire dans tous les profils.

## 7. Front : environnements Angular

`environment.ts` (dev), `environment.test.ts` (config Angular `test`), `environment.production.ts` (image). Les trois fixent `apiBaseUrl: 'http://localhost:8080'`.
