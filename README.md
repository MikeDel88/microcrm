<p align="center">
   <img src="./front/src/favicon.png" width="192px" />
</p>

# MicroCRM (P7 - Développeur Full-Stack - Java et Angular - Mettez en œuvre l'intégration et le déploiement continu d'une application Full-Stack)

MicroCRM est une application de démonstration basique ayant pour être objectif de servir de socle pour le module "P7 - Développeur Full-Stack".

L'application MicroCRM est une implémentation simplifiée d'un ["CRM" (Customer Relationship Management)](https://fr.wikipedia.org/wiki/Gestion_de_la_relation_client). Les fonctionnalités sont limitées à la création, édition et la visualisations des individus liés à des organisations.

![Page d'accueil](./misc/screenshots/screenshot_1.png)
![Édition de la fiche d'un individu](./misc/screenshots/screenshot_2.png)

## Code source

### Organisation

Ce [monorepo](https://en.wikipedia.org/wiki/Monorepo) contient les 2 composantes du projet "MicroCRM":

- La partie serveur (ou "backend"), en Java Spring Boot 4 (Java 17, Gradle 8.14);
- La partie cliente (ou "frontend"), en Angular 17.

### Démarrer avec les sources

#### Serveur

##### Dépendances

- [OpenJDK >= 17](https://openjdk.org/)

##### Procédure

1. Se positionner dans le répertoire `back` avec une invite de commande:

   ```shell
   cd back
   ```

2. Construire le JAR:

   ```shell
   # Sur Linux
   ./gradlew build

   # Sur Windows
   gradlew.bat build
   ```

3. Démarrer le service:

   ```shell
   java -jar build/libs/microcrm.jar
   ```

Puis ouvrir l'URL http://localhost:8080 dans votre navigateur.

#### Client

##### Dépendances

- [NPM >= 10.2.4](https://www.npmjs.com/)

##### Procédure

1. Se positionner dans le répertoire `front` avec une invite de commande:

   ```shell
   cd front
   ```

2. (La première fois seulement) Installer les dépendances NodeJS:

   ```shell
   npm install
   ```

3. Démarrer le service de développement:

   ```shell
   npx @angular/cli serve
   ```

Puis ouvrir l'URL http://localhost:4200 dans votre navigateur.

### Exécution des tests

#### Client

**Dépendances**

- Google Chrome ou Chromium

Dans votre terminal:

```shell
cd front
CHROME_BIN=</path/to/google/chrome> npm test
```

#### Serveur

Dans votre terminal:

```shell
cd back
./gradlew test
```

### Images Docker

#### Client

##### Construire l'image

```shell
docker build --target front -t orion-microcrm-front:latest .
```

##### Exécuter l'image

```shell
docker run -it --rm -p 80:80 -p 443:443 orion-microcrm-front:latest
```

L'application sera disponible sur https://localhost.

#### Serveur

##### Construire l'image

```shell
docker build --target back -t orion-microcrm-back:latest .
```

##### Exécuter l'image

```shell
docker run -it --rm -p 8080:8080 orion-microcrm-back:latest
```

L'API sera disponible sur http://localhost:8080.

#### Front et back avec Docker Compose

```shell
docker compose up --build
```

L'application sera disponible sur https://localhost et l'API sur http://localhost:8080. Par défaut, le back utilise le profil `dev` ; pour un autre profil : `SPRING_PROFILES_ACTIVE=prod docker compose up --build`. Le front ne démarre qu'une fois le back *healthy* (`/actuator/health`). Orchestration décrite dans `compose.yml`, choix techniques dans [documentation/08-conteneurisation.md](documentation/08-conteneurisation.md).

#### Supervision (ELK)

```shell
./elk.sh up     # ./elk.sh down pour arrêter
```

Prérequis, tableau de bord Kibana et détails : [documentation/11-supervision-elk.md](documentation/11-supervision-elk.md).

## CI/CD

Pipeline GitHub Actions (`.github/workflows/ci.yml` et `cd.yml`), images publiées dans GHCR. Voir la [documentation](documentation/archives/CICD-synthese.md) et, pour lancer chaque étape, [documentation/01-pipeline-ci-cd.md](documentation/archives/01-pipeline-ci-cd.md).

- CI (build, tests, SonarQube Cloud) : [documentation/07-pipeline-ci.md](documentation/07-pipeline-ci.md)
- Publication des images et déploiement : [documentation/09-deploiement.md](documentation/09-deploiement.md)
- Releases GitHub (versions, changelog, artefacts) : [documentation/10-release.md](documentation/10-release.md)
- Plan de déploiement (étapes, ordre, prérequis, rollback) : [documentation/14-plan-deploiement.md](documentation/14-plan-deploiement.md)
