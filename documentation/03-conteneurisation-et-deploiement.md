# Principes de conteneurisation et de déploiement

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

Le `Dockerfile` du dépôt est multi-stage et définit cinq étapes (deux de compilation, trois cibles d'exécution) :

| Étape | Rôle |
|-------|------|
| `front-build` | Compile l'application Angular (`npm ci`, `ng build`) |
| `back-build` | Compile l'application Spring Boot (`./gradlew build`) et produit le JAR |
| `front` (cible) | Image d'exécution : Caddy sert les fichiers statiques du front |
| `back` (cible) | Image d'exécution : JRE qui lance le JAR |
| `standalone` (cible) | Front et back dans une seule image, pilotés par supervisord |

La CI construit une image par cible avec `docker build --target <cible>`.

### 2.2 Analyse du Dockerfile actuel

| Constat | Risque | Amélioration |
|---------|--------|--------------|
| Images `node` et `gradle:jdk17` non épinglées | Builds non reproductibles, changement de version silencieux | Épingler la version (`node:20-alpine`, `gradle:8-jdk17`), voire le digest |
| JDK 17 au build, JRE 21 à l'exécution | Code compilé et exécuté sur deux versions différentes | Aligner les deux sur la même version |
| Exécution en root | Surface d'attaque en cas de compromission | Créer un utilisateur dédié (`USER`) |
| Cible `standalone` : deux processus dans un conteneur (supervisord) | Un processus mort n'est pas détecté par Docker, journaux et redémarrages mélangés | Réserver `standalone` au test de fumée et à la démonstration ; déployer front et back séparément |
| `EXPOSE 4200` sur l'image `back` | Spring Boot écoute sur 8080 par défaut : indication trompeuse | Vérifier le port réel et corriger |
| Aucun `HEALTHCHECK` | Impossible de savoir si le service répond | Ajouter un healthcheck sur chaque cible |
| `RUN ./gradlew build` lance aussi les tests | Les tests sont exécutés deux fois (CI puis build d'image) | Utiliser `-x test` dans l'image, les tests étant déjà validés en amont |

À noter : l'URL de l'API est écrite en dur dans le front (`front/src/app/config.ts` : `http://localhost:8080`). Elle est donc figée à la compilation, ce qui est **incompatible avec le principe « une seule image pour tous les environnements »**. Il faut une configuration lue à l'exécution (fichier de configuration servi par Caddy, ou chemin relatif `/api` transmis au back par Caddy en reverse proxy) pour que la même image fonctionne en dev, pré-production et production.

### 2.3 Docker Compose

Le dépôt ne contient aucun fichier Compose aujourd'hui. Il est prévu d'en ajouter un, dont les rôles sont :

| Rôle | Détail |
|------|--------|
| **Décrire l'application** | Services `front`, `back` et, selon le choix de persistance, `db` ; réseau interne ; volume de données |
| **Déployer un environnement** | `docker compose pull && docker compose up -d` sur la machine cible |
| **Servir de test dans la CI** | Démarrer l'application complète pour le test de fumée (PR vers `main`) et pour les tests e2e |
| **Reproduire en local** | Un développeur lance l'ensemble avec une seule commande |

Organisation proposée :

| Fichier | Contenu |
|---------|---------|
| `compose.yml` | Définition commune : services, réseau, volumes, healthchecks. L'image est référencée par variable (`image: ghcr.io/…/microcrm-back:${IMAGE_TAG}`) |
| `compose.dev.yml` / `compose.preprod.yml` / `compose.prod.yml` | Spécificités de l'environnement (ports, nombre de réplicas, limites de ressources) |
| `.env.<environnement>` | Variables non secrètes (tag d'image, URLs). **Les secrets ne sont jamais dans ces fichiers** : ils viennent de GitHub Environments |

- Le tag d'image est fourni au déploiement (`IMAGE_TAG=sha-3f2a9c1`) : changer de version ou revenir en arrière revient à changer cette valeur.
- Les volumes contiennent la base persistante, ce qui rend possible la sauvegarde et la restauration (partie 1, § 3.6).

## 3. Registre et versionnement des images

Les images sont publiées dans un registre (GitHub Container Registry, `ghcr.io`, à confirmer), une image par cible : `microcrm-front`, `microcrm-back`, `microcrm-standalone`.

### 3.1 Quand une image est construite

Conformément au plan de testing (partie 1), **aucune image n'est construite sur un push de `features/*` ou `fix/*`** : ces pushes ne lancent que les tests et le contrôle de qualité.

| Événement | Image construite | Publiée dans le registre |
|-----------|------------------|--------------------------|
| Push sur `features/*` ou `fix/*` | Non | – |
| PR vers `develop` | Non | – |
| PR vers `main` | Oui, pour le scan Trivy et le test de fumée | Non (image jetable, supprimée à la fin du job) |
| Fusion sur `develop` | Oui | Oui, tags SHA, `develop`, `X.Y.Z-SNAPSHOT` |
| Fusion sur `main` | Oui | Oui, tags SHA, `main`, version |

### 3.2 Tags appliqués à chaque build publié

| Tag | Exemple | Nature | Rôle |
|-----|---------|--------|------|
| **SHA du commit** | `sha-3f2a9c1` | Immuable | Identifie l'image de façon unique et la relie au commit exact. **C'est la référence utilisée pour déployer et promouvoir.** |
| **Nom de la branche** | `develop`, `main` | Mobile (déplacé à chaque build) | Retrouver facilement le dernier build d'une branche |
| **Version + `-SNAPSHOT`** (branche `develop` uniquement) | `1.3.0-SNAPSHOT` | Mobile (reconstruit à chaque fusion tant que la version ne change pas) | Indique la **version en cours de développement** ; reprend la version du JAR Gradle ; signale une image **non destinée à la production** |
| **Version** (branche `main` uniquement) | `v1.2.0` | Immuable | Release identifiable, utilisée pour la production et le retour arrière |

### 3.3 Règles

- **Les tags mobiles ne servent jamais à déployer** : un déploiement cible un tag immuable (SHA ou version), ou mieux, le *digest* de l'image (`@sha256:…`), afin que ce qui est déployé soit exactement ce qui a été testé.
- **Pas de tag `latest`** : ambigu et mobile. En cas de besoin, il désignerait la dernière version stable de `main`.
- Les tags `X.Y.Z-SNAPSHOT` et de branche sont **mobiles par nature** ; ils n'ont de valeur que pour la commodité.
- **Cycle de version** : `develop` porte la version à venir suffixée (`1.3.0-SNAPSHOT`). À la livraison sur `main`, le suffixe est retiré et l'image reçoit `v1.3.0` ; `develop` passe ensuite à la version suivante (`1.4.0-SNAPSHOT`).
- **Source unique de la version** : la version vient de `version` dans `back/build.gradle` (aujourd'hui `0.0.1-SNAPSHOT`) et est lue par le workflow pour calculer les tags, afin qu'elle ne soit jamais saisie à la main. Le front a sa propre version dans `package.json` (aujourd'hui `0.0.0`) : il faut les aligner ou décider laquelle fait foi.
- L'image promue de la pré-production à la production est la **même** (même SHA, même digest), avec en plus le tag de version (§ 4.2).

### 3.4 Nettoyage

- Les images `develop` (`X.Y.Z-SNAPSHOT`) conservent les N derniers builds (par exemple 20).
- Les images versionnées (`vX.Y.Z`) sont conservées, car elles permettent le retour arrière.
- Les images de plus de 6 mois sans usage sont revues lors de la tâche hebdomadaire.

### 3.5 Publication et sécurité

- Seules les fusions sur `develop` et sur `main` publient des images ; les PR construisent au plus une image jetable, jamais publiée.
- Le jeton de publication est limité à l'écriture de paquets (`packages: write`) et n'est exposé qu'aux workflows concernés (voir plan de sécurité).
- Chaque image publiée est scannée (Trivy) avant promotion.

## 4. Environnements et stratégie de déploiement

### 4.1 Les trois environnements

| Environnement | Branche source | Déclencheur | Rôle |
|---------------|----------------|-------------|------|
| **Dev** | `develop` | Déploiement automatique après chaque fusion de PR sur `develop` | Intégration continue sur une vraie instance ; cible des tests e2e nocturnes sur `develop` |
| **Pré-production** (staging) | `main` | Déploiement automatique après chaque fusion de PR sur `main` | Réplique de la production : dernière validation avant mise en ligne ; cible des tests e2e nocturnes sur `main` et du test de sauvegarde / restauration hebdomadaire |
| **Production** | `main` (même image que la pré-prod) | Déploiement **manuel**, après approbation | Environnement des utilisateurs |

### 4.2 Principe de promotion

- L'image Docker est **construite une seule fois**, à la fusion sur `main`, puis **promue** telle quelle de la pré-production vers la production : on ne reconstruit pas. Ce qui a été testé en pré-prod est exactement ce qui part en prod.
- Le passage en production exige une approbation (GitHub Environments avec relecteurs requis), donnée après vérification en pré-production.
- Le flux complet est : `features/*` ou `fix/*` → PR → `develop` (déployé en dev) → PR → `main` (déployé en pré-prod) → approbation → production.

### 4.3 Ce que « ressembler à la production » signifie

La pré-production doit différer de la production le moins possible, afin que les tests y aient de la valeur :

- même image Docker, mêmes versions de Java et de Caddy ;
- même configuration (variables d'environnement, ports, `Caddyfile`), seules les valeurs propres à l'environnement changeant (URL, secrets) ;
- même type de base de données, avec des données anonymisées ou de démonstration, **jamais des données réelles non anonymisées** ;
- mêmes règles réseau et mêmes protections (HTTPS, en-têtes).

Chaque environnement a ses propres secrets, définis dans GitHub Environments, de façon à ce qu'un secret de production ne soit jamais accessible depuis dev ou pré-prod.

### 4.4 Stratégie de déploiement et publication des images

Le déploiement suit une chaîne unique, dans laquelle chaque étape conditionne la suivante :

| # | Étape | Où | Condition de passage |
|---|-------|----|----------------------|
| 1 | **Build** des images (cibles `front` et `back`) | Runner GitHub Actions | Tests, qualité et sécurité au vert sur la PR (partie 1 et 2) |
| 2 | **Scan** des images (Trivy) | Runner | Aucune vulnérabilité au-dessus du seuil (plan de sécurité) |
| 3 | **Publication** dans le registre, avec les tags du § 3.2 | GHCR | Scan réussi ; uniquement après fusion sur `develop` ou `main` |
| 4 | **Déploiement** de l'image par SHA ou digest | Serveur de l'environnement | Image publiée |
| 5 | **Vérification** : healthcheck puis test de fumée | Environnement déployé | Les services répondent dans le délai défini |
| 6 | **Retour arrière automatique** si l'étape 5 échoue | Environnement | Retour à la version précédente (§ 5) |

Mise en œuvre par environnement :

| Environnement | Déclencheur | Tag déployé | Validation |
|---------------|-------------|-------------|-----------|
| Dev | Fusion sur `develop` | SHA du commit (aussi tagué `X.Y.Z-SNAPSHOT`) | Automatique |
| Pré-production | Fusion sur `main` | SHA du commit (aussi tagué `vX.Y.Z`) | Automatique ; tests e2e nocturnes |
| Production | Lancement manuel du workflow de déploiement | **Le même SHA que la pré-production**, sans reconstruction | Approbation d'un relecteur via GitHub Environments |

- Le déploiement est réalisé par un workflow `deploy.yml`, qui se connecte à la machine cible (SSH) et exécute `docker compose pull` puis `docker compose up -d` avec le tag d'image voulu. La connexion utilise des secrets propres à l'environnement.
- Le déploiement est **idempotent** : relancer le workflow avec le même tag ne change rien.
- Un seul déploiement à la fois par environnement (`concurrency` GitHub Actions), pour éviter deux mises à jour simultanées.
- Les déploiements sont **tracés** : GitHub Environments conserve l'historique (qui, quand, quelle version).
- Stratégie de mise en ligne : remplacement direct des conteneurs avec vérification de santé, suffisant pour ce projet. Un déploiement bleu/vert ou progressif serait une évolution possible, non retenue ici car elle double les ressources nécessaires.

*Hébergement cible (serveur, cloud, plateforme) : à définir.* Le mode SSH + Docker Compose décrit ci-dessus suppose un serveur ou une machine virtuelle sur lesquels Docker est installé ; une plateforme managée demanderait d'adapter l'étape 4.

## 5. Retour arrière (rollback)

*À rédiger.*

## 6. Lien avec les plans de test et de sécurité

*Quels contrôles conditionnent le déploiement.*
