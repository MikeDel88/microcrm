# Principes de conteneurisation et de déploiement

> **Scénario A (pipeline idéal).** La version adaptée à l'état actuel du projet figure au chapitre 5.

## 1. Principes de conteneurisation

| Principe | Application à MicroCRM |
|----------|------------------------|
| **Build multi-stage** | Les outils de compilation (Node, Gradle, JDK) restent dans les étapes de build ; l'image finale ne contient que le nécessaire à l'exécution |
| **Images de base épinglées** | Version précise (voire digest) plutôt que `node` ou `gradle:jdk17` : build reproductible |
| **Utilisateur non-root** | Le processus de l'application ne s'exécute pas en root |
| **Un processus par conteneur** | Front et back dans deux conteneurs distincts, orchestrés par Docker Compose |
| **Image identique d'un environnement à l'autre** | Seule la configuration change (variables d'environnement, secrets), jamais l'image |
| **`.dockerignore`** | Exclure `node_modules`, `build`, `.git`, fichiers d'IDE : contexte léger, aucune fuite de fichier sensible |
| **Healthchecks** | Chaque service déclare comment vérifier qu'il fonctionne |
| **Aucun secret dans l'image** | Les secrets sont injectés à l'exécution |

## 2. Rôle des Dockerfile et de Docker Compose

Les deux fichiers ont des rôles distincts et complémentaires :

| | **Dockerfile** | **Docker Compose** |
|---|---|---|
| Question à laquelle il répond | *Comment construire une image ?* | *Comment faire tourner l'ensemble des conteneurs ?* |
| Produit | Une image, publiée dans le registre | Un environnement en fonctionnement (réseau, volumes, services) |
| Utilisé par | Le job de build de la CI | Le déploiement, le test de fumée, les tests e2e, le poste du développeur |
| Change quand | Le code ou ses dépendances changent | La topologie ou la configuration d'un environnement change |

### 2.1 Le Dockerfile

Le `Dockerfile` du dépôt est multi-stage et définit quatre étapes (deux de compilation, deux cibles d'exécution) :

| Étape | Rôle |
|-------|------|
| `front-build` | Compile l'application Angular (`npm ci`, puis `npm run build`) sur `node:20-alpine` |
| `back-build` | Compile l'application Spring Boot 4 (`./gradlew bootJar -x test`) et produit le JAR ; la version de Gradle (8.14.5) du `Dockerfile` est alignée sur celle du wrapper |
| `front` (cible) | Image d'exécution : Caddy sert les fichiers statiques du front |
| `back` (cible) | Image d'exécution : JRE qui lance le JAR |

La CI construit une image par cible avec `docker build --target <cible>`.

### 2.2 Analyse du Dockerfile

#### Corrections déjà appliquées (détail au chapitre 6)

| Constat initial | Correction |
|-----------------|-----------|
| Images `node` et `gradle:jdk17` non épinglées | `node:20-alpine` (compatible Angular 17), `gradle:8.7-jdk17-alpine` (version du wrapper), `caddy:2.11.7-alpine` à la place d'`alpine:3.19` |
| JDK 17 au build, JRE 21 à l'exécution | `eclipse-temurin:17-jre-alpine` (JRE 17) |
| `EXPOSE 4200` sur l'image `back` | `EXPOSE 8080` |
| `RUN ./gradlew build` relançait les tests | `bootJar -x test`, les tests étant validés en amont |
| Cache Docker inefficace (code copié avant les dépendances) | Front : `package*.json` puis `npm ci` puis le code. Back : fichiers Gradle et `dependencies` avant le code |
| `npx @angular/cli build` : version de la CLI non figée | `npm run build`, version du `package-lock.json` |
| Cible `standalone` (supervisord, deux processus) | Supprimée ; front et back tournent dans deux conteneurs via Compose |
| Aucun `HEALTHCHECK` sur le back | `wget` sur `/organizations` (`curl` absent d'Alpine) |
| Exécution en root | Utilisateur `app` sur `front` et `back` (l'image officielle Caddy autorise les ports 80/443 en non-root) |
| Aucun `HEALTHCHECK` sur le front | `nc -z localhost 80` (Caddy redirige HTTP vers HTTPS, un `wget` suivrait la redirection vers un certificat auto-signé) |
| JAR nommé en dur avec la version (`microcrm-0.0.1-SNAPSHOT.jar`) | `archiveFileName = 'microcrm.jar'` dans `build.gradle`, utilisé par le `Dockerfile` et `supervisor.ini` |

#### Restant à corriger

| Constat | Risque | Amélioration |
|---------|--------|--------------|
| Images de base épinglées par tag, pas par digest | Le tag peut bouger | Épingler le digest (`@sha256:…`), mis à jour par Dependabot |
| `JAVA_OPTS` absent | Mémoire du JVM non bornée dans le conteneur | `-XX:MaxRAMPercentage=75` dans la commande de démarrage |
À noter : l'URL de l'API est écrite en dur dans le front (`front/src/environments/environment.production.ts` : `http://localhost:8080`). Elle est donc figée à la compilation, ce qui est **incompatible avec le principe « une seule image pour tous les environnements »**. Il faut une configuration lue à l'exécution (fichier de configuration servi par Caddy, ou chemin relatif `/api` transmis au back par Caddy en reverse proxy) pour que la même image fonctionne en développement, test, pré-production et production.

### 2.3 Docker Compose

Le dépôt contient `compose.yml` (services `front` et `back`) et les surcharges `compose.dev.yml` et `compose.test.yml`. Les rôles prévus sont :

| Rôle | Détail |
|------|--------|
| **Décrire l'application** | Services `front`, `back` et, selon le choix de persistance, `db` ; réseau interne ; volume de données |
| **Déployer un environnement** | `docker compose pull && docker compose up -d` sur la machine cible |
| **Servir de test dans la CI** | Démarrer l'application complète pour le test de fumée (PR vers `main`) et pour les tests e2e |
| **Reproduire en local** | Un développeur lance l'ensemble avec une seule commande |

Organisation proposée :

| Fichier | Contenu |
|---------|---------|
| `compose.yml` | Définition commune : services `front` et `back`, ports, `build:` depuis le `Dockerfile` (cibles `front` et `back`). **Sans `image:`** : la CI construit ainsi l'image depuis le Dockerfile, ce qui vérifie qu'elle se construit |
| `compose.dev.yml` / `compose.test.yml` | Profil Spring (`dev`, `test`) ; healthcheck du back en test |
| `compose.release.yml` | **Exécution des images publiées dans GHCR**, sans build local : `image: ghcr.io/mikedel88/microcrm-{back,front}:${TAG}`, `pull_policy: always`, profil Spring forcé (`prod` par défaut, `RELEASE_PROFILE` pour le changer) |
| `compose.preprod.yml` / `compose.prod.yml` (à créer) | Spécificités de l'environnement (ports, nombre de réplicas, limites de ressources) |
| `.env.<environnement>` | Variables non secrètes (tag d'image, URLs). **Les secrets ne sont jamais dans ces fichiers** : ils viennent de GitHub Environments |

- Le tag d'image est fourni au déploiement par la variable `TAG` (obligatoire dans `compose.release.yml`, version `X.Y.Z` ou SHA) : changer de version ou revenir en arrière revient à changer cette valeur.

Quelle commande pour quel usage :

| Besoin | Commande |
|--------|----------|
| Développer avec **mon code local** (build depuis le Dockerfile) | `docker compose -f compose.yml -f compose.dev.yml up --build` |
| Tester l'état de `develop` sans compiler (back seul ou front seul à développer, démo, poste sans JDK/Node) | `TAG=SNAPSHOT RELEASE_PROFILE=dev docker compose -f compose.yml -f compose.release.yml up -d` |
| Faire tourner une version publiée | `TAG=1.2.0 docker compose -f compose.yml -f compose.release.yml up -d` |
| Test de fumée en CI | `docker compose -f compose.yml -f compose.test.yml up -d --build --wait` |

Le développement garde le `build:` local : l'image `SNAPSHOT` reflète le dernier état fusionné de `develop`, pas la branche `feature/*` en cours, et elle supprime la boucle courte modifier-reconstruire-tester. Les images GHCR sont privées tant que le package n'est pas rendu public (sinon `docker login ghcr.io` préalable). Il n'existe pas encore de `application-prod.properties` : le profil `prod` utilise `application.properties` seul.
- Les volumes contiennent la base persistante, ce qui rend possible la sauvegarde et la restauration (partie 1, § 3.6).

## 3. Registre et versionnement des images

Les images sont publiées dans un registre (GitHub Container Registry, `ghcr.io`, à confirmer), une image par cible : `microcrm-front`, `microcrm-back`, `microcrm-standalone`.

### 3.1 Quand une image est construite

Conformément au plan de testing (partie 1), **aucune image n'est construite sur un push de `features/*` ou `fix/*`** : ces pushes ne lancent que les tests et le contrôle de qualité.

| Événement | Image construite | Publiée dans le registre |
|-----------|------------------|--------------------------|
| Push sur `features/*` ou `fix/*` | Non | – |
| PR vers `develop` | Oui, pour vérifier le build et le test de fumée | Non (image jetable) |
| PR vers `main` | Oui, pour le test de fumée et le scan Trivy | Non (image jetable, supprimée à la fin du job) |
| Fusion sur `develop` | Oui : build, test de fumée, puis push | Oui, tags SHA, `develop`, `SNAPSHOT` |
| Fusion sur `main` | Oui : build, test de fumée, puis push | Oui, tags SHA, `main`, puis `X.Y.Z` et `latest` si semantic-release crée une version |

### 3.2 Tags appliqués à chaque build publié

| Tag | Exemple | Nature | Rôle |
|-----|---------|--------|------|
| **SHA du commit** | `sha-3f2a9c1` | Immuable | Identifie l'image de façon unique et la relie au commit exact. **C'est la référence utilisée pour déployer et promouvoir.** |
| **Nom de la branche** | `develop`, `main` | Mobile (déplacé à chaque build) | Retrouver facilement le dernier build d'une branche |
| **`SNAPSHOT`** (branche `develop` uniquement) | `SNAPSHOT` | Mobile (déplacé à chaque fusion sur `develop`) | Dernier build d'intégration ; signale une image **non destinée à la production** |
| **Version** (branche `main` uniquement) | `1.2.0` (tag Git `v1.2.0`) | Immuable | Release calculée par semantic-release, posée par retag du SHA testé ; utilisée pour la production et le retour arrière |
| **`latest`** (branche `main` uniquement) | `latest` | Mobile | Dernière version stable |

### 3.3 Règles

- **Les tags mobiles ne servent jamais à déployer** : un déploiement cible un tag immuable (SHA ou version), ou mieux, le *digest* de l'image (`@sha256:…`), afin que ce qui est déployé soit exactement ce qui a été testé.
- **`latest`** est mobile et ne sert pas à déployer ; il désigne la dernière version stable de `main`.
- Les tags `SNAPSHOT` et de branche sont **mobiles par nature** ; ils n'ont de valeur que pour la commodité.
- **Cycle de version** : pas de branches `release/*`. À la fusion sur `main`, semantic-release déduit la version des commits conventionnels (`feat:` → mineure, `fix:` → correctif, `BREAKING CHANGE` → majeure), crée le tag Git `vX.Y.Z`, met à jour `CHANGELOG.md` et l'image `:sha` déjà testée reçoit les tags `X.Y.Z` et `latest`.
- **Source unique de la version** : l'historique Git (commits conventionnels et tags). La `version` de `back/build.gradle` et celle du `package.json` du front ne font pas foi pour les images. Le secret `RELEASE_TOKEN` (PAT) est requis pour pousser le changelog sur `main` protégée.
- L'image promue de la pré-production à la production est la **même** (même SHA, même digest), avec en plus le tag de version (§ 4.2).

### 3.4 Nettoyage

- Les images `develop` (SHA, `SNAPSHOT`) conservent les N derniers builds (par exemple 20).
- Les images versionnées (`X.Y.Z`) sont conservées, car elles permettent le retour arrière.
- Les images de plus de 6 mois sans usage sont revues lors de la tâche hebdomadaire.

### 3.5 Valider avant la fusion, publier après

Le build est vérifié **avant** la fusion (sur la PR) et la publication a lieu **après** : une fois la PR fusionnée, plus rien ne peut empêcher la fusion, il faut donc que l'essentiel soit prouvé avant.

| Moment | Étapes | Si échec |
|--------|--------|----------|
| **PR** (vers `develop` ou `main`) | Build de l'image, test de fumée ; sur `main`, scan Trivy en plus | La fusion est bloquée |
| **Fusion** | Workflow de publication : **build, test de fumée, scan, puis push**, puis SBOM et tag de version | Rien n'est publié ; voir § 3.8 |

- L'image publiée est reconstruite sur le commit de fusion, qui peut différer de celui testé dans la PR. Le test de fumée est donc **rejoué avant le push** : on ne publie jamais une image qui n'a pas démarré.
- Ainsi, seule une cause d'infrastructure (registre, permissions, réseau) peut encore faire échouer la dernière étape.

### 3.6 Publication et sécurité

- Seules les fusions sur `develop` et sur `main` publient des images ; les PR construisent au plus une image jetable, jamais publiée.
- Le jeton de publication est limité à l'écriture de paquets (`packages: write`) et n'est exposé qu'aux workflows concernés (voir plan de sécurité).
- Chaque image publiée est scannée (Trivy) avant promotion.

### 3.7 SBOM publié avec chaque image

Chaque image publiée est accompagnée de son **SBOM** (inventaire de ses composants, format CycloneDX), généré sur l'image elle-même et non sur le code source : il inclut ainsi les paquets de l'OS, le JRE et Caddy (plan de sécurité, « SBOM »).

| Aspect | Règle |
|--------|-------|
| Génération | Étape du workflow de publication, **après le push** de l'image et sur son digest, avec Trivy ou Syft (`docker buildx build --sbom=true` est une alternative qui l'attache à l'image) |
| Identification | Le SBOM porte le SHA de l'image : il décrit exactement ce qui est déployé |
| Stockage | Artefact du workflow ; pour `main`, **joint à la release `vX.Y.Z`** |
| Durée | Identique à celle de l'image (§ 3.4) |
| Rescan | Hebdomadaire, sur les SBOM des images en pré-production et en production (partie 1, § 3.5) |
| Condition de déploiement | Un SBOM doit exister pour le SHA à déployer, au même titre que l'image publiée et scannée (§ 6.2) |

- Un SBOM par cible publiée (`front`, `back`).
- La génération n'est pas bloquante pour le build, mais son absence l'est pour la **promotion vers la production**.

### 3.8 Échec après la fusion

Si le workflow de publication échoue après la fusion, le code est déjà intégré mais **rien n'est publié ni déployé** : la version précédente reste en place.

1. **Relancer le workflow** (*Re-run jobs* ou `workflow_dispatch`) si la cause est temporaire (réseau, registre). La publication repart du même SHA.
2. **Corriger en avant** : nouvelle PR avec le correctif (les branches étant protégées, c'est le chemin normal).
3. **Revert** : PR qui annule le commit fautif si le correctif prend du temps.
4. L'image `:sha` est publiée avant la release ; les tags `X.Y.Z` et `latest` ne sont posés qu'après le scan Trivy. Si le scan échoue, relancer après correctif : une release Git sans image versionnée est possible et se corrige par un retag manuel.
5. L'échec déclenche une notification et une issue. Tant que `develop` ou `main` est en échec, aucune nouvelle fusion n'est faite avant correction.

## 4. Environnements et stratégie de déploiement

### 4.1 Les quatre environnements

Deux environnements servent à **construire et vérifier** (développement, test), deux à **livrer** (pré-production, production). Chacun a sa propre configuration (§ 4.3).

| Environnement | Branche source | Déclencheur | Rôle |
|---------------|----------------|-------------|------|
| **Développement** (dev) | `features/*`, `fix/*` | Manuel, sur le poste du développeur (`docker compose` avec `compose.dev.yml`, ou `ng serve` + `gradlew bootRun`) | Développer et déboguer une feature ou un correctif ; base en mémoire ou données de démonstration, logs détaillés, aucun secret réel |
| **Test** | PR, puis `develop` | Runner GitHub Actions (conteneurs jetables) sur chaque PR ; déploiement automatique après chaque fusion de PR sur `develop` | Exécuter les tests (unitaires, intégration, test de fumée, e2e) avec une configuration dédiée, jamais celle de dev ; cible des tests e2e nocturnes sur `develop` |
| **Pré-production** (staging) | `main` | Déploiement automatique après chaque fusion de PR sur `main` | Réplique de la production : dernière validation avant mise en ligne ; cible des tests e2e nocturnes sur `main` et du test de sauvegarde / restauration hebdomadaire |
| **Production** | `main` (même image que la pré-prod) | Déploiement **manuel**, après approbation | Environnement des utilisateurs |

### 4.2 Principe de promotion

- L'image Docker est **construite une seule fois**, à la fusion sur `main`, puis **promue** telle quelle de la pré-production vers la production : on ne reconstruit pas. Ce qui a été testé en pré-prod est exactement ce qui part en prod.
- Le passage en production exige une approbation (GitHub Environments avec relecteurs requis), donnée après vérification en pré-production.
- Le flux complet est : `features/*` ou `fix/*` (développées en **dev**) → PR (tests en CI avec la configuration **test**) → `develop` (déployé en **test**) → PR → `main` (déployé en pré-prod) → approbation → production.

### 4.3 Ce que « ressembler à la production » signifie

La pré-production doit différer de la production le moins possible, afin que les tests y aient de la valeur :

- même image Docker, mêmes versions de Java et de Caddy ;
- même configuration (variables d'environnement, ports, `Caddyfile`), seules les valeurs propres à l'environnement changeant (URL, secrets) ;
- même type de base de données, avec des données anonymisées ou de démonstration, **jamais des données réelles non anonymisées** ;
- mêmes règles réseau et mêmes protections (HTTPS, en-têtes).

Chaque environnement a ses propres secrets, définis dans GitHub Environments, de façon à ce qu'un secret de production ne soit jamais accessible depuis dev, test ou pré-prod.

**Configuration par environnement.** L'image est la même ; seule la configuration change, choisie par un profil Spring (`SPRING_PROFILES_ACTIVE`) côté back et par une configuration lue à l'exécution côté front.

| | Développement | Test | Pré-production | Production |
|---|---|---|---|---|
| Profil Spring | `dev` | `test` | `preprod` | `prod` |
| Fichier back | `application-dev.properties` | `application-test.properties` | `application-preprod.properties` | `application-prod.properties` |
| URL de l'API (front) | `http://localhost:8080` | URL de l'instance de test ou du service Compose | URL de pré-prod | URL de production |
| Base de données | HSQLDB en mémoire / démo | Jetable, recréée à chaque exécution | Persistante, données anonymisées | Persistante, données réelles |
| Logs / débogage | Détaillés, endpoints de débogage permis | Détaillés | Niveau production | Niveau production, aucun endpoint de débogage |
| Secrets | Aucun secret réel (valeurs factices) | GitHub Environments `test` | GitHub Environments `preprod` | GitHub Environments `prod` |

État actuel : les profils `dev` et `test` existent (`application-dev.properties`, `application-test.properties`) ainsi que les environnements Angular (`environment.ts`, `environment.test.ts`, `environment.production.ts`). Restent à créer `preprod` et `prod`, et à rendre l'URL de l'API lisible à l'exécution (aujourd'hui fixée à la compilation).

### 4.4 Stratégie de déploiement et publication des images

Le déploiement suit une chaîne unique, dans laquelle chaque étape conditionne la suivante :

| # | Étape | Où | Condition de passage |
|---|-------|----|----------------------|
| 1 | **Build** des images (cibles `front` et `back`) | Runner GitHub Actions | Tests, qualité et sécurité au vert sur la PR (partie 1 et 2) |
| 2 | **Scan** des images (Trivy) | Runner | Aucune vulnérabilité au-dessus du seuil (plan de sécurité) |
| 3 | **Publication** dans le registre, avec les tags du § 3.2, puis génération du SBOM (§ 3.7) | GHCR | Scan réussi ; uniquement après fusion sur `develop` ou `main` |
| 4 | **Déploiement** de l'image par SHA ou digest | Serveur de l'environnement | Image publiée |
| 5 | **Vérification** : healthcheck puis test de fumée | Environnement déployé | Les services répondent dans le délai défini |
| 6 | **Retour arrière automatique** si l'étape 5 échoue | Environnement | Retour à la version précédente (§ 5) |

Mise en œuvre par environnement :

| Environnement | Déclencheur | Tag déployé | Validation |
|---------------|-------------|-------------|-----------|
| Développement | Aucun déploiement : lancement local | Tag choisi ou build local | Aucune |
| Test | PR (runner jetable), puis fusion sur `develop` | SHA du commit (aussi tagué `SNAPSHOT`) | Automatique ; tests e2e nocturnes |
| Pré-production | Fusion sur `main` | SHA du commit (aussi tagué `X.Y.Z`) | Automatique ; tests e2e nocturnes |
| Production | Lancement manuel du workflow de déploiement | **Le même SHA que la pré-production**, sans reconstruction | Approbation d'un relecteur via GitHub Environments |

- Le déploiement est réalisé par un workflow `deploy.yml`, qui se connecte à la machine cible (SSH) et exécute `docker compose pull` puis `docker compose up -d` avec le tag d'image voulu. La connexion utilise des secrets propres à l'environnement.
- Le déploiement est **idempotent** : relancer le workflow avec le même tag ne change rien.
- Un seul déploiement à la fois par environnement (`concurrency` GitHub Actions), pour éviter deux mises à jour simultanées.
- Les déploiements sont **tracés** : GitHub Environments conserve l'historique (qui, quand, quelle version).
- Stratégie de mise en ligne : remplacement direct des conteneurs avec vérification de santé, suffisant pour ce projet. Un déploiement bleu/vert ou progressif serait une évolution possible, non retenue ici car elle double les ressources nécessaires.

*Hébergement cible (serveur, cloud, plateforme) : à définir.* Le mode SSH + Docker Compose décrit ci-dessus suppose un serveur ou une machine virtuelle sur lesquels Docker est installé ; une plateforme managée demanderait d'adapter l'étape 4.

## 5. Retour arrière (rollback)

*Condition d'activation : au moins un environnement déployé (phase 2). Le workflow `rollback.yml` et la sauvegarde avant déploiement relèvent de la phase 3.*

### 5.1 Principe

Le retour arrière consiste à **redéployer une image précédente, sans rien reconstruire**. Il est possible parce que :

- chaque image publiée a un tag **immuable** (SHA, `vX.Y.Z`) conservé dans le registre (§ 3.2 et 3.4) : la version précédente existe toujours, identique à ce qui a été testé ;
- le déploiement est piloté par une seule valeur, `IMAGE_TAG`, passée à Docker Compose (§ 2.3) : changer de version, avant ou arrière, revient à changer cette valeur.

On ne s'appuie **jamais sur un tag mobile** (`main`, `develop`) pour revenir en arrière : il désigne déjà la version défaillante.

### 5.2 Mémoriser la version précédente

À chaque déploiement réussi, le workflow enregistre le tag qui était en place avant la mise à jour :

- dans un fichier sur le serveur de l'environnement (par exemple `previous.env` contenant `IMAGE_TAG=sha-…`), et
- dans l'historique des déploiements de GitHub Environments (version, auteur, date).

Seule la version **déployée avec succès** est retenue comme version précédente.

### 5.3 Cas de la pré-production en échec

Le déploiement en pré-production suit la fusion d'une PR sur `main`. Si les healthchecks ou le test de fumée échouent :

1. **Retour automatique** : le workflow redéploie le tag précédent (`IMAGE_TAG` restauré, puis `docker compose up -d`) et vérifie à nouveau la santé.
2. **Notification et issue** : l'équipe est prévenue et une issue est créée (version défaillante, version restaurée, lien vers l'exécution), comme pour les échecs nocturnes.
3. **Production protégée** : la production n'est jamais déployée tant que la pré-production n'est pas saine (§ 4.2). Elle reste donc sur sa version précédente ; rien n'est à restaurer côté production.
4. **Correction** : `main` contient pourtant le code défaillant. Comme `main` est protégée (PR obligatoire), on corrige par une nouvelle PR : soit un **revert** du commit fautif, soit un correctif. La CI repasse, une nouvelle image est publiée et déployée.

### 5.4 Retour arrière manuel

Un workflow `rollback.yml` (déclenchement manuel, `workflow_dispatch`) permet de revenir à une version choisie, y compris en production :

| Paramètre | Rôle |
|-----------|------|
| Environnement | `test`, `preprod` ou `prod` |
| Tag à déployer | Un tag immuable existant dans le registre (SHA ou `vX.Y.Z`) ; par défaut, la version précédente enregistrée |

- Pour la production, le workflow demande la même **approbation** qu'un déploiement normal.
- Il vérifie que le tag existe, déploie, puis exécute healthchecks et test de fumée.
- Le retour arrière est **rapide** (quelques minutes) car aucune compilation n'est nécessaire.

### 5.5 La base de données : le point délicat

Redéployer une ancienne image **ne défait pas** les modifications de la base. Un retour arrière peut échouer si la nouvelle version a modifié la structure ou les données.

- **Sauvegarde avant chaque déploiement** en pré-production et en production (dump ou volume, selon la méthode retenue en partie 1, § 3.6), pour pouvoir restaurer si nécessaire.
- **Modifications de schéma compatibles avec la version précédente** : ajouter avant de supprimer (une colonne ajoutée n'empêche pas l'ancienne version de tourner ; une colonne supprimée si). Le retrait se fait dans une version ultérieure.
- Si une restauration de base est nécessaire, elle est déclenchée manuellement, car elle fait perdre les données écrites depuis la sauvegarde.
- Aujourd'hui, la base est en mémoire (HSQLDB sans configuration) et se réinitialise à chaque démarrage : le problème n'existe pas encore, mais apparaîtra dès que la base sera persistante.

### 5.6 Limites

- Le retour arrière automatique suppose une version précédente **saine** : au premier déploiement d'un environnement, il n'y en a pas.
- Un retour automatique répété (boucle) est évité : une seule tentative, puis arrêt et alerte.
- Un défaut qui n'apparaît qu'après quelques heures (fuite mémoire, erreur sur un cas rare) n'est pas détecté par le test de fumée ; les tests e2e nocturnes et la surveillance servent à le repérer, et le retour arrière manuel est alors utilisé.

## 6. Lien avec les plans de test et de sécurité

Le déploiement n'est pas une étape isolée : il n'a lieu que si les contrôles des parties 1 et 2 ont réussi. Chaque étape ouvre la suivante, et un échec l'arrête.

### 6.1 Les contrôles qui conditionnent chaque étape

| Étape | Contrôles à réussir | Défini en |
|-------|---------------------|-----------|
| Push sur `features/*` ou `fix/*` | Tests unitaires et d'intégration, qualité (SonarQube Cloud), détection de secrets | Partie 1 § 3.2, partie 2 § 4 |
| PR vers `develop` | Idem, plus SAST (CodeQL), dépendances et licences, scan du `Dockerfile`, build de l'image et test de fumée ; relecture et approbation | Partie 1 § 3.2, partie 2 § 4 et 6 |
| Fusion sur `develop` | Build, test de fumée, scan, puis publication | § 3.5 |
| **Déploiement en test** | Image publiée et scannée ; healthcheck | § 4.4 |
| PR vers `main` | Tous les contrôles précédents, plus scan des images (Trivy) ; relecture et approbation | Partie 1 § 3.2 d) |
| **Déploiement en pré-production** | Fusion sur `main` ; image publiée et scannée ; healthcheck puis test de fumée | § 4.4 |
| **Déploiement en production** | Pré-production saine ; approbation manuelle ; **même image** que la pré-production | § 4.2 |

### 6.2 Le déploiement est bloqué quand…

- un test, le contrôle de qualité ou le quality gate échoue ;
- une vulnérabilité au-dessus du seuil est détectée dans le code, les dépendances ou l'image (critique et élevée, plan de sécurité § 4) ;
- un secret est détecté dans le code ;
- la PR n'a pas été relue et approuvée, ou ses conversations ne sont pas résolues ;
- le test de fumée ou les healthchecks échouent (avec retour arrière, § 5) ;
- il n'y a pas d'image publiée pour le SHA à déployer ;
- le SBOM de l'image n'existe pas, pour une promotion vers la production.

Ces blocages sont appliqués par les **règles de protection de branche** et par les **vérifications requises** : ils ne reposent pas sur la discipline des développeurs.

### 6.3 Ce qui n'arrête pas le déploiement, mais le signale

Les contrôles périodiques surveillent des environnements déjà en ligne et ne bloquent pas un déploiement en cours ; un échec produit une **notification et une issue** :

| Contrôle | Fréquence | Effet d'un échec |
|----------|-----------|------------------|
| Tests e2e sur test (`develop`) et pré-production (`main`) | Chaque nuit | Issue ; à traiter avant le prochain déploiement en production |
| Audit des dépendances | Chaque nuit | Issue ; correction dans le délai prévu (plan de sécurité § 7) |
| Rebuild sans cache et scan des images | Chaque semaine | Issue ; mise à jour des images de base |
| Sauvegarde et restauration de la base | Chaque semaine | Issue ; la restauration doit être corrigée avant tout déploiement qui modifie la base |

- **Règle proposée** : une issue nocturne ou hebdomadaire ouverte et non résolue sur la pré-production fait l'objet d'une vérification avant l'approbation du déploiement en production. Le relecteur doit explicitement la lever ou la reporter.
- Les vulnérabilités critiques détectées sur une version **déjà en production** déclenchent un correctif rapide (48 heures, plan de sécurité § 7), même hors cycle normal de livraison.

### 6.4 Ce que chaque plan apporte au déploiement

| Plan | Garantie apportée |
|------|-------------------|
| Plan de testing (partie 1) | Le code **fonctionne** et reste de qualité ; il continue de fonctionner dans le temps (nuit, semaine) ; les données peuvent être restaurées |
| Plan de sécurité (partie 2) | Le code, les dépendances et les images ne contiennent pas de faille connue au-dessus du seuil ; les secrets sont protégés ; le circuit de livraison est contrôlé |
| Conteneurisation et déploiement (partie 3) | Ce qui a été testé et scanné est **exactement** ce qui est livré ; la mise en ligne est tracée, vérifiée et réversible |

Le point commun est l'**image immuable identifiée par son SHA** : elle est testée, scannée, publiée puis déployée sans être modifiée. Tous les contrôles s'appliquent à la même chose que celle qui part en production.
