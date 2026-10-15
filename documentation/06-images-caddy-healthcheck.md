# Images Docker, Caddy et HEALTHCHECK

> Ce chapitre complète le chapitre 3 (§ 2) : il explique les choix faits dans le `Dockerfile` actuel (images de base, suppression de la cible `standalone`, nom du JAR), le rôle de Caddy et les `HEALTHCHECK`.

## 1. Structure actuelle du `Dockerfile`

| Étape | Image de base | Rôle |
|-------|---------------|------|
| `front-build` | `node:20-alpine` | Compile l'application Angular (`npm ci`, `npm run build`) |
| `back-build` | `gradle:8.7-jdk17-alpine` | Compile le back (`./gradlew --no-daemon bootJar -x test`) et produit `microcrm.jar` |
| `front` (cible) | `caddy:2.11.7-alpine` | Sert les fichiers statiques du front |
| `back` (cible) | `eclipse-temurin:17-jre-alpine` | Exécute le JAR avec un JRE seul |

Les étapes de compilation ne sont pas livrées : seuls les résultats (`dist/…/browser` et le JAR) sont copiés dans les images d'exécution, ce qui les garde petites.

## 2. Changement des images de base

Avant, toutes les cibles d'exécution partaient de `alpine:3.19`, sur lequel on installait les paquets (`apk add caddy`, `apk add openjdk21-jre-headless`).

| Cible | Avant | Après | Raison |
|-------|-------|-------|--------|
| Build front | `node` (sans version) | `node:20-alpine` | Angular 17 exige Node 18.13+ ou 20.9+ ; version figée pour des builds reproductibles ; image plus légère |
| Build back | `gradle:jdk17` | `gradle:8.7-jdk17-alpine` | Version de Gradle alignée sur le wrapper (`gradle-wrapper.properties`) |
| Exécution front | `alpine:3.19` + `apk add caddy` | `caddy:2.11.7-alpine` | Image officielle maintenue par l'éditeur ; plus de paquet à installer |
| Exécution back | `alpine:3.19` + `openjdk21-jre-headless` | `eclipse-temurin:17-jre-alpine` | JRE seul, officiel ; **JRE 17 aligné sur le JDK 17 du build** (le code était compilé en 17 et exécuté en 21) |

Pourquoi quitter `alpine:3.19` :
- cette version n'est plus supportée, donc plus de correctifs de sécurité ;
- installer les paquets soi-même impose de suivre leurs mises à jour ;
- une image officielle par rôle réduit les paquets inutiles, donc la surface d'attaque.

Aucune image n'est sans faille. Ce qui compte est de réduire la surface, de **scanner** (Trivy, voir le plan de sécurité), de **reconstruire** chaque semaine et d'épingler les versions (tag précis, idéalement digest, mis à jour par Dependabot).

### Autres changements du `Dockerfile`

| Changement | Détail |
|------------|--------|
| **Cache Docker** | Front : `package*.json` puis `npm ci` puis le code. Back : fichiers Gradle et `dependencies` avant le code. Une modification de code ne retélécharge plus les dépendances |
| **`bootJar -x test`** | Les tests sont validés en CI avant la construction de l'image ; ils ne sont plus relancés dans l'image |
| **`--no-daemon`** | Gradle ne laisse pas de processus en arrière-plan dans un build jetable |
| **`EXPOSE 8080`** | Le back écoutait sur 8080 mais déclarait 4200 |
| **Utilisateur `app`** | `front` et `back` ne s'exécutent plus en root |
| **`npm run build`** | Au lieu de `npx @angular/cli build`, qui téléchargeait une CLI non figée ; la version vient du `package-lock.json` |

### Suppression de la cible `standalone`

La cible `standalone` regroupait Caddy et Java dans une seule image, pilotés par **supervisord** (`misc/docker/supervisor.ini`), pour un `docker run` unique.

Elle a été supprimée, avec `supervisor.ini` et la section « Tout en un » du README :

- Docker ne surveille qu'un processus ; si Caddy ou Java plantait, le conteneur restait « vivant » ;
- logs et redémarrages des deux services étaient mélangés ;
- front et back ne pouvaient être mis à jour ni déployés séparément ;
- l'image cumulait deux piles (Caddy, JRE) plus supervisord, donc plus de paquets à scanner ;
- elle imposait de rester en root.

Remplacement : **Docker Compose** (`compose.yml`), qui lance deux conteneurs distincts. Le test de fumée en CI utilise `compose.yml` + `compose.test.yml`. Les workflows d'exemple (`ci.yml`, `publish.yml`, `weekly.yml`) ne construisent plus que `front` et `back`.

### Nom du JAR fixe : `microcrm.jar`

`back/build.gradle` fixe `bootJar { archiveFileName = 'microcrm.jar' }`. Avant, le fichier s'appelait `microcrm-0.0.1-SNAPSHOT.jar`, nom écrit en dur dans le `Dockerfile` (et dans `supervisor.ini`) : chaque changement de version cassait le `COPY` et le `CMD`.

- Le nom est stable ; seul `build.gradle` porte la version.
- La version est portée par le **tag de l'image** (SHA, `X.Y.Z-SNAPSHOT`, `vX.Y.Z`, voir chapitre 3, § 3.2) et les métadonnées du JAR, pas par le nom du fichier.
- Un nom sans version convient à un JAR placé dans une image à usage unique. Si le JAR était publié comme artefact (Maven, release), le nom devrait au contraire porter la version.

## 3. Caddy

### Rôle

Angular produit des fichiers statiques (HTML, JS, CSS). Un serveur web doit les distribuer au navigateur : c'est le rôle de **Caddy** dans l'image `front`. Il ne sert pas de proxy vers le back ; le navigateur appelle directement l'API.

### Configuration (`misc/docker/Caddyfile`)

```
* {
	root * /app/front
	encode gzip
	try_files {path} /index.html
	file_server
}
```

| Directive | Effet |
|-----------|-------|
| `*` | S'applique à tous les noms d'hôte. Sans port, Caddy active le **HTTPS automatique** : écoute en 443 avec un certificat auto-signé et redirection du port 80 vers 443 |
| `root * /app/front` | Dossier des fichiers servis (le build Angular copié par le `Dockerfile`) |
| `encode gzip` | Compresse les réponses |
| `try_files {path} /index.html` | Renvoie `index.html` si le fichier n'existe pas, pour que le routeur Angular gère les routes (`/persons/3`) et qu'un rafraîchissement ne donne pas de 404 |
| `file_server` | Active le service de fichiers statiques |

### Dans l'image

- `COPY misc/docker/Caddyfile /app/Caddyfile` ; démarrage par `caddy run --config /app/Caddyfile`. Avec l'image officielle, le binaire est `caddy` (dans `/usr/bin`) ; l'ancien chemin `/usr/sbin/caddy` n'existe plus.
- Le navigateur affiche un avertissement de certificat en local : l'application est servie sur **https://localhost**.
- Caddy fonctionne avec l'utilisateur `app` sur les ports 80/443 : l'image officielle donne au binaire la capacité de lier des ports privilégiés.

### Alternatives écartées

| Option | Intérêt | Pourquoi écartée |
|--------|---------|------------------|
| `nginxinc/nginx-unprivileged` | Non-root nativement | Réécriture de la config, perte du HTTPS automatique |
| Image distroless / `scratch` | Surface minimale | Difficile à déboguer, pas de `HEALTHCHECK` en shell |

## 4. HEALTHCHECK

Un `HEALTHCHECK` est une commande que Docker exécute régulièrement dans le conteneur. Son code de retour donne l'état : `starting`, `healthy` ou `unhealthy` (visible avec `docker ps`).

À quoi il sert :
- savoir si le service **répond**, et pas seulement si le processus existe ;
- ordonner les démarrages : `docker compose up --wait` attend que les conteneurs soient `healthy` ;
- servir de base au test de fumée en CI et au retour arrière après déploiement (chapitre 3, § 5).

### Définitions actuelles

| Cible | Commande | Intervalle / délai de démarrage |
|-------|----------|--------------------------------|
| `back` | `wget -q -O /dev/null http://localhost:8080/organizations \|\| exit 1` | 10 s / 30 s (le démarrage de Spring est lent) |
| `front` | `nc -z localhost 80 \|\| exit 1` | 10 s / 10 s |

Pourquoi ces commandes :
- `curl` n'est pas installé sur Alpine ; `wget` et `nc` sont fournis par BusyBox.
- Le back est interrogé sur une vraie route de l'API : elle valide Spring, JPA et la base.
- Le front est testé avec `nc` (le port 80 est ouvert) : un `wget` sur `http://localhost` suivrait la redirection vers HTTPS et échouerait sur le certificat auto-signé. Ce test vérifie que Caddy écoute, pas que la page se charge.
- `--start-period` laisse du temps au démarrage sans compter d'échec.

### Où ils sont utilisés

- `compose.test.yml` définit aussi un healthcheck sur le back pour `docker compose up --wait` en CI.
- Une image sans `HEALTHCHECK` oblige à redéfinir la vérification dans Compose ; celui de l'image s'applique partout.

### Limites

- `nc` ne prouve pas que le front sert correctement la page : le test de fumée en CI (`curl -k https://localhost/`) complète la vérification.
- Un healthcheck trop strict ou trop fréquent peut redémarrer un service sain ; ces valeurs sont à ajuster à l'usage.

## 5. Ce qui reste à faire

| Point | Remarque |
|-------|----------|
| Digest des images de base (`@sha256:…`) | Mis à jour par Dependabot |
| `JAVA_OPTS` (`-XX:MaxRAMPercentage=75`) | Borner la mémoire du JVM dans le conteneur |
| `LABEL` OCI (source, version, licence) | Traçabilité dans GHCR |
| URL de l'API lue à l'exécution | Aujourd'hui fixée à la compilation (chapitre 3, § 2.2) |
