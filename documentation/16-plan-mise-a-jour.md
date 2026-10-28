# Plan de mise à jour

Objectif : expliquer **comment MicroCRM est mis à jour**, **comment ses dépendances sont gérées**, et quelles **bonnes pratiques** suivre pour garder la solution à jour. Ce plan s'appuie sur :
- les versions et releases ([10](10-release.md)) ;
- le plan de déploiement ([14](14-plan-deploiement.md)) ;
- le plan de sécurité ([05](05-plan-securite.md)) ;
- l'analyse SonarQube ([13](13-analyse-sonar.md)).

État au **28/10/2026**.

## 1. Comment l'application est mise à jour

Toute modification, qu'il s'agisse d'une fonctionnalité, d'un correctif ou d'une mise à jour de dépendance, suit **la même chaîne**. Aucune mise à jour n'est faite directement sur un serveur.

```
branche ─► PR vers develop ─► CI ─► fusion ─► CD + RC vX.Y.Z-rc.N ─► PRÉPROD (TAG=X.Y.Z-rc.N) ─► validation
                                                                                                         │ OK
                                        PROD (TAG=X.Y.Z) ◄─ CD + version vX.Y.Z ◄─ fusion ◄─ PR vers main ◄┘
```

**1. Le type de commit fixe le type de version** (*Conventional Commits*, calcul par semantic-release) :

| Commit | Version produite | Exemple |
|---|---|---|
| `fix(...)` | correctif : 1.1.3 → **1.1.4** | correction d'un bug, ou mise à jour de sécurité d'une dépendance livrée |
| `feat(...)` | évolution : 1.1.3 → **1.2.0** | nouvelle fonctionnalité |
| `feat(...)!` ou `BREAKING CHANGE:` | majeure : 1.1.3 → **2.0.0** | changement incompatible (API, configuration) |
| `chore`, `docs`, `ci`, `test` | pas de version | outillage, documentation |

**2. Une version passe d'abord par la préproduction.** La fusion sur `develop` produit une release candidate (`X.Y.Z-rc.N`) et ses images. On la déploie sur le **serveur de préproduction** (section 2), où elle est testée dans des conditions proches de la production. Elle n'est fusionnée sur `main` qu'une fois validée.

**3. La mise en service en production** se fait avec le tag de version, par la même procédure que celle déjà répétée en préproduction :

```shell
TAG=X.Y.Z docker compose -f compose.yml -f compose.release.yml pull    # téléchargement, l'application tourne encore
TAG=X.Y.Z docker compose -f compose.yml -f compose.release.yml up -d   # recréation des conteneurs : back, puis front
```

Compose arrête puis recrée les conteneurs : une **courte interruption** a lieu, le temps du démarrage du back. Tant que la base est en mémoire, les données repartent du jeu de démonstration. Le détail est dans [14](14-plan-deploiement.md).

**4. En cas de problème**, on revient à la version précédente avec la même commande et l'ancien tag (`TAG=X.Y.W`). Il n'y a pas de rebuild : l'image est toujours dans GHCR.

## 2. Serveur de préproduction

Aujourd'hui, une release candidate n'est testée que sur un poste de développement. Ce poste ne ressemble pas à un serveur : configuration différente, pas de vraies données, pas de procédure de mise à jour répétée. Le **serveur de préproduction** comble cet écart. C'est une copie de la production, sur laquelle **chaque mise à jour est jouée avant d'atteindre la production**.

### Ce qu'il doit reproduire

| Élément | En préproduction | Pourquoi |
|---|---|---|
| Serveur | même système, même version de Docker et de Compose que la production ; dimensionnement proche | une mise à jour qui passe en préprod doit passer en prod pour les mêmes raisons |
| Fichiers de déploiement | les **mêmes** `compose.yml` et `compose.release.yml`, profil Spring `prod` | on teste la procédure de production, pas une variante |
| Images | les images de la RC, `TAG=X.Y.Z-rc.N`, tirées de GHCR | l'image validée est celle qui sera promue |
| Base de données | même moteur et même version que la production ; données issues du **dump nocturne de production, anonymisé** ([15](15-plan-sauvegarde.md)) | tester les migrations de schéma et le comportement sur un volume réaliste, sans exposer de données personnelles |
| Secrets | **propres à la préprod**, gérés dans le coffre ([15](15-plan-sauvegarde.md)) | une fuite en préprod ne doit jamais compromettre la production |
| Supervision | stack ELK branchée comme en production | vérifier l'absence de nouvelles erreurs `ERROR` après la mise à jour ; c'est aussi l'environnement où la fréquence des erreurs devient mesurable avec un trafic de référence ([12](12-dora-kpi.md)) |
| Accès | réservé à l'équipe : réseau privé ou authentification devant Caddy | la préprod n'est pas un environnement public |

### Ce qu'on y teste avant chaque mise en production

| Test | Contrôle | Critère de passage |
|---|---|---|
| Procédure de mise à jour | `pull`, puis `up -d` depuis la version actuellement en production | les deux services sont *healthy* ; durée de l'interruption mesurée |
| Tests de fumée | santé, API, front ([14](14-plan-deploiement.md) §C) | tous au vert |
| Tests fonctionnels | parcours principaux : créer, modifier et supprimer une personne et une organisation | aucun écart avec la version précédente |
| Migration des données | démarrage sur la copie anonymisée de la base de production | schéma migré, données lisibles, aucune perte |
| Retour arrière | redéploiement de la version précédente (`TAG=X.Y.W`) | l'application revient à l'état précédent ; la procédure est prête si la production échoue |
| Supervision | Kibana pendant au moins 24 h | pas de nouvelle erreur `ERROR` |

Pour une **montée de version majeure** (Spring Boot 4, Angular 22, Node 22…), la RC reste en préproduction plus longtemps, plusieurs jours si besoin. On y vérifie aussi la consommation de ressources (mémoire, CPU via Metricbeat).

### Déploiement en préproduction

- **Déclenchement** : à chaque nouvelle RC. Le déploiement peut se faire à la main au début, puis être automatisé par un job ajouté à `release.yml` après `publish`, limité aux tags `-rc` et protégé par un *environment* GitHub `preprod`.
- **Production** : le déploiement reste déclenché par une personne (*environment* GitHub `production` avec approbation obligatoire), et seulement pour une version dont la RC a été validée en préproduction.

## 3. Gestion des dépendances

### Inventaire

| Composant | Version actuelle | Comment la version est fixée | Support |
|---|---|---|---|
| Java | 17 | `sourceCompatibility`, image `eclipse-temurin:17-jre-alpine`, CI | LTS, supportée |
| Spring Boot (et Spring, Tomcat) | **3.2.5** | plugin Gradle `org.springframework.boot` ; les bibliothèques Spring sont alignées par le BOM (`io.spring.dependency-management`) | **fin du support open source en novembre 2024** ; CVE critiques acceptées jusqu'au 31/01/2027 (`.trivyignore`) |
| Autres bibliothèques back | `logback-ecs-encoder` 1.6.0, `spring-boot-data-fixtures` 0.2.0 | version explicite dans `build.gradle` | à surveiller |
| Gradle | 8.7 | wrapper (`gradle-wrapper.properties`), image `gradle:8.7.0-jdk17-alpine` | à mettre à jour avec Spring Boot |
| Angular | **17.3** | plages `^17.3.0` + `package-lock.json` + `npm ci` | **fin du support en mai 2025** ; 8 vulnérabilités dans le code livré (4 *high*), corrigées seulement en Angular 22 |
| Node.js (build du front) | **20** | image `node:20-alpine`, `NODE_VERSION: 20` dans la CI | **fin de vie en avril 2026** |
| Caddy | 2.11.7 | image `caddy:2.11.7-alpine` | à jour |
| Stack ELK | 8.17.0 | `STACK_VERSION` dans `.env.elk` | à surveiller |
| Outillage de release | semantic-release 24 | `package.json` racine + lockfile | outil de CI, non livré |
| Actions GitHub | `actions/checkout@v7`, `docker/build-push-action@v6`… | version majeure dans les workflows | à surveiller |

État des vulnérabilités au 28/10/2026 (`npm audit`) :
- **front, dépendances livrées** : 8 vulnérabilités (4 *high*, 4 *moderate*), toutes dans les paquets `@angular/*` 17 ;
- **front, outillage de build et de test** : 84 de plus, dont 5 *critical*. Elles ne sont pas embarquées dans l'image, mais touchent le poste de développement et la CI ;
- **back** : CVE de Tomcat et Spring Framework détectées par Trivy, acceptées et datées ([09](09-deploiement.md)).

### Principes

| Principe | Mise en œuvre dans MicroCRM |
|---|---|
| **Builds reproductibles** | `package-lock.json` versionné et `npm ci` (jamais `npm install` en CI) ; wrapper Gradle ; BOM Spring Boot ; images de base à version fixe |
| **Une seule source de version par composant** | la version de Spring Boot pilote toutes les bibliothèques Spring ; une version unique d'Angular pour tous les paquets `@angular/*` ; `NODE_VERSION` et l'image Node alignés |
| **Détection automatique** | à chaque fusion, Trivy scanne les images (en place) ; à mettre en place : **Dependabot** (npm, Gradle, Docker, GitHub Actions), revue des dépendances des PR et `npm audit` ([05](05-plan-securite.md), priorité 2) |
| **Chaque mise à jour est une PR** | une PR par dépendance ou par groupe cohérent (par exemple tous les `@angular/*`), validée par la CI comme tout autre changement |
| **Commit adapté à l'impact** | `fix(deps): …` pour une dépendance livrée, ce qui produit une version corrective déployable ; `chore(deps): …` pour l'outillage, qui ne produit pas de version |

### Traiter une mise à jour selon son type

| Type | Exemple | Traitement | Délai |
|---|---|---|---|
| **Correctif de sécurité** (critique ou *high*) | CVE dans Tomcat | PR immédiate, `fix(deps)`, RC, version corrective, déploiement | **sous 7 jours** (critique : au plus vite) |
| **Patch ou mineure** | Angular 17.3.x, Spring Boot 3.2.x | PR Dependabot, CI verte, fusion groupée | chaque semaine |
| **Majeure** | Angular 17 → 18, Spring Boot 3 → 4 | branche dédiée, **une version majeure à la fois**, guide de migration de l'éditeur, outils de migration (`ng update`, OpenRewrite pour Spring), tests complets et validation prolongée de la RC en préproduction | planifiée, au plus une par trimestre et par composant |
| **Fin de vie (EOL)** | Node 20, Angular 17 | traitée comme une majeure, avant la date d'EOL | à anticiper de 3 mois |

## 4. Feuille de route des mises à jour

Par ordre de priorité, d'après l'inventaire :

| # | Mise à jour | Pourquoi | Méthode | Échéance |
|---|---|---|---|---|
| 1 | **Spring Boot 3.2.5 → 3.5, puis 4.x** (avec Gradle à la version requise) | version hors support ; CVE critiques acceptées seulement jusqu'au 31/01/2027 | d'abord surcharger `tomcat.version` (10.1.58) pour vider une partie de `.trivyignore`, puis monter par étapes (3.3, 3.4, 3.5, 4.0) en suivant les notes de migration | **avant le 31/01/2027** |
| 2 | **Angular 17 → 22** | version hors support ; 4 vulnérabilités *high* dans le code livré | `ng update @angular/core@18 @angular/cli@18`, puis 19, 20, 21, 22, avec la CI et une RC validée en préproduction à chaque étape. On en profite pour corriger les alertes Sonar du front ([13](13-analyse-sonar.md)) | T1 2027 |
| 3 | **Node 20 → 22 LTS** | Node 20 est en fin de vie | changer `node:20-alpine` dans le `Dockerfile` et `NODE_VERSION` dans les workflows, en même temps ; vérifier la compatibilité avec la version d'Angular visée | avec l'étape 2 |
| 4 | **Outillage du front** (Karma, ESLint, typescript-eslint) | 84 vulnérabilités hors code livré | mis à jour avec Angular ; Karma, déprécié, à remplacer par le lanceur de tests proposé par Angular | avec l'étape 2 |
| 5 | **Stack ELK 8.17 → dernière 8.x** | rester dans une version maintenue | changer `STACK_VERSION`, puis redémarrer la stack (les données ELK ne sont pas critiques, voir [15](15-plan-sauvegarde.md)) | T1 2027 |
| 6 | **Java 17 → 21** (optionnel) | 17 est encore supportée ; 21 est la LTS suivante | après Spring Boot 4 : `sourceCompatibility`, image `eclipse-temurin:21-jre-alpine`, `JAVA_VERSION` en CI | à évaluer |

## 5. Bonnes pratiques pour maintenir la solution à jour

**Mettre à jour souvent, par petits pas**
- Plusieurs petites mises à jour par mois coûtent moins cher qu'une grande migration par an. MicroCRM en est l'illustration : Angular a aujourd'hui **5 versions majeures** de retard.
- Ne jamais sauter de version majeure : chaque étape a son guide de migration et ses outils.

**Automatiser la détection**
- Activer Dependabot sur les quatre écosystèmes (npm, Gradle, Docker, GitHub Actions), avec des PR regroupées par famille.
- Garder Trivy bloquant en CD. Toute exception va dans `.trivyignore`, avec une **date d'expiration** et une justification.
- Réintroduire `npm audit` et la revue des dépendances dans la CI ([05](05-plan-securite.md)).

**Ne fusionner que ce qui est testé**
- Toute mise à jour passe par la CI (`ci-ok`) et le quality gate Sonar, puis par une RC validée sur le serveur de préproduction (section 2). Aucune mise à jour ne part en production sans y être passée.
- La couverture de tests conditionne la sécurité des mises à jour : 56 % pour le back, 26 % pour le front ([13](13-analyse-sonar.md)). La remonter réduit le risque de régression silencieuse lors d'une montée de version.

**Garder la maîtrise des versions**
- Lockfiles versionnés, `npm ci`, wrapper Gradle, images de base à version fixe. Jamais de tag `latest`.
- Aligner les versions là où elles sont dupliquées : Node dans le `Dockerfile` et dans la CI ; Java dans `build.gradle`, dans les images et dans la CI.

**Surveiller les fins de vie**
- Vérifier chaque trimestre les dates de fin de support de Java, Spring Boot, Angular, Node et Elastic (par exemple sur endoflife.date), et planifier la migration au moins 3 mois avant.

**Tracer et pouvoir revenir en arrière**
- Une mise à jour de dépendance livrée produit une version (`fix(deps)`) : elle apparaît dans le `CHANGELOG.md` et peut être déployée ou annulée par son tag.
- Garder la version précédente disponible pour un retour arrière immédiat (`TAG=X.Y.W`).

### Rythme

| Fréquence | Action |
|---|---|
| Chaque semaine | revue et fusion des PR Dependabot (patchs, mineures, sécurité) |
| Chaque mois | lecture des rapports `npm audit` et Trivy ; réexamen des issues Sonar |
| Chaque trimestre | revue des fins de vie ; planification d'une montée majeure ; réexamen des exceptions `.trivyignore` |
| Avant chaque mise en production | RC validée en préproduction (tests de la section 2) ; plus aucune exception expirée ; dépendances livrées sans vulnérabilité *high* ou *critical* connue |
