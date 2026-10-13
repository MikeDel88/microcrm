# Plan de testing périodique

> **Scénario A (pipeline idéal).** La version adaptée à l'état actuel du projet figure au chapitre 5.

## 1. Objectifs

Le plan de testing définit à quelle fréquence chaque type de test est exécuté automatiquement, et dans quel but. Le principe : **plus la fréquence est élevée, plus les tests doivent être rapides** ; les contrôles longs ou coûteux sont déplacés sur des cycles plus espacés.

| Objectif | Moyen |
|----------|-------|
| Détecter une régression au plus tôt | Tests rapides à chaque push et pull request |
| Garantir que `main` est toujours livrable | Build et test de fumée de l'image sur chaque PR ; build, test de fumée puis publication à chaque merge |
| Détecter les dérives non liées au code (dépendances, images de base) | Exécutions planifiées, la nuit et chaque semaine |
| Garder une trace mesurable de la qualité | Rapports de tests et de couverture conservés comme artefacts |

## 2. Typologie des tests

| Niveau | Back (Spring Boot / JUnit) | Front (Angular / Karma + Jasmine) | Rapidité |
|--------|----------------------------|-----------------------------------|----------|
| Unitaires | `MicroCRMApplicationTests` (chargement du contexte) | 6 fichiers `*.spec.ts` (composants et services) | Secondes à minutes |
| Intégration | `PersonRepositoryIntegrationTest` (repository + base) | – | Minutes |
| End-to-end | – | Non existant : à introduire, exécuté chaque nuit (voir § 3.4) | Plusieurs minutes |

Constat : la couverture actuelle est faible côté back (deux classes de test). Le plan prévoit de mesurer d'abord la couverture réelle (§ 5) avant d'imposer des seuils.

## 3. Calendrier d'exécution (quand)

### 3.1 Vue d'ensemble

| Fréquence | Déclencheur GitHub Actions | Tests exécutés | Objectif |
|-----------|----------------------------|----------------|----------|
| À chaque push sur `features/*` ou `fix/*` | `push` avec filtre `branches: [features/**, fix/**]` | Tests fonctionnels (unitaires et d'intégration) back et front, **contrôle de la qualité du code**, **détection de secrets**, build des deux applications | Retour rapide au développeur (cible < 10 min) avant même d'ouvrir une PR |
| À chaque pull request vers `develop` | `pull_request` ciblant `develop` | Mêmes contrôles que sur push (tests, qualité, couverture) **plus sécurité et dépendances, build de l'image et test de fumée** | Condition obligatoire avant la revue et la validation de la PR |
| À chaque pull request vers `main` | `pull_request` ciblant `main` | Tous les contrôles d'une PR vers `develop`, **plus scan des images Docker (Trivy)** | Prouver que ce qui va être livré est construisible, sain et démarre |
| À chaque fusion de PR sur `develop` ou `main` | `push` sur `develop` / `main` (résultat de la fusion) | Tout ce qui précède, plus **build, test de fumée, scan puis publication** des images (partie 3, § 3.5) | Vérifier que la branche reste stable et livrable après intégration |
| Toutes les nuits | `schedule` : `0 2 * * *` (02:00 UTC), sur `develop` **et** `main` | Suite complète depuis un cache vierge, **tests end-to-end**, audit des dépendances | Détecter une régression introduite par une dépendance externe ou un test instable ; en cas d'échec : notification et création d'une issue |
| Toutes les semaines | `schedule` : `0 3 * * 0` (dimanche, 03:00 UTC) | Rebuild des images sans cache, scan de vulnérabilités, **sauvegarde et test de restauration de la base de données**, revue des tests instables | Contrôle en profondeur et mise à jour des images de base |

### 3.1 bis Tests par environnement

| Environnement | Configuration | Tests concernés |
|---------------|---------------|-----------------|
| Développement (poste) | Profil `dev` | Lancement manuel des tests unitaires pendant le travail sur une feature ou un fix ; aucun résultat n'est considéré comme une validation |
| Test (CI, puis instance `develop`) | Profil `test`, base jetable | Tous les tests automatisés : unitaires, intégration, test de fumée, e2e nocturnes sur `develop` ; jamais exécutés avec la configuration `dev` |
| Pré-production | Profil `preprod` | E2e nocturnes sur `main`, sauvegarde et test de restauration |
| Production | Profil `prod` | Aucun test automatisé (test de fumée de déploiement uniquement) |

### 3.2 Modèle de branches, push et pull request

Les modifications suivent ce flux :

1. Le développeur travaille sur une branche **`features/*`** (nouvelle fonctionnalité) ou **`fix/*`** (correctif). Chaque push déclenche la CI.
2. Il n'y a **aucun push direct sur `develop` ni sur `main`** : toute modification de ces branches passe obligatoirement par une **pull request**. Cette interdiction est appliquée par les règles de protection de branche de GitHub (y compris pour les administrateurs), et non par simple convention.
3. La PR déclenche à nouveau la CI. Elle ne peut être fusionnée que si les tests passent **et** qu'elle a été relue et approuvée par au moins un relecteur (voir plan de sécurité).
4. Après fusion, la CI s'exécute sur la branche cible (§ 3.3). Techniquement, la fusion d'une PR produit un événement `push` : c'est celui-ci que les workflows écoutent, il ne s'agit pas d'un push de développeur.
5. Le cheminement complet est : `features/*` ou `fix/*` → PR → `develop` → PR → `main`.

À chaque push sur `features/*` ou `fix/*`, deux familles de contrôles sont exécutées :

**a) Tests fonctionnels** (le code fait ce qu'il doit faire)

- Back : `./gradlew test` depuis `back/`.
- Front : `npm ci` puis `ng test --watch=false --browsers=ChromeHeadless` depuis `front/`.
- Build : `./gradlew build` et `ng build`.

**b) Qualité du code** (le code est lisible, maintenable et sans défaut évident)

| Contrôle | Back | Front | Ce qui est vérifié |
|----------|------|-------|--------------------|
| Analyse statique / style | Checkstyle ou SpotBugs (à choisir) | ESLint (`ng lint`, à ajouter) | Conventions, bugs probables, code mort |
| Couverture de tests | JaCoCo | Karma `--code-coverage` | Part du code exercée par les tests |
| Synthèse et « quality gate » | SonarQube Cloud (rôle détaillé dans le plan de sécurité) | idem | Duplication, dette technique, code smells, seuils sur le code nouveau |

- Le contrôle de qualité s'exécute dans un job **parallèle** aux tests, pour ne pas allonger le temps total.
- Un échec du quality gate fait échouer le pipeline, au même titre qu'un test en échec.
- On applique les seuils au **code nouveau ou modifié** uniquement : cela évite de bloquer toute contribution à cause de la dette existante.
- Aujourd'hui, aucun de ces outils n'est configuré dans le dépôt (`build.gradle` et `package.json` ne contiennent ni Jacoco, ni Checkstyle, ni Sonar, ni script de lint). Leur ajout fait partie de la mise en place.

**c) Sécurité et dépendances (en plus, uniquement sur pull request)**

Lors d'une PR vers `develop` (ou `main`), on ajoute aux contrôles précédents :

| Contrôle | Outil envisagé | Ce qui est vérifié |
|----------|----------------|--------------------|
| Analyse de sécurité du code (SAST) | CodeQL (Java et TypeScript) | Failles dans le code : injection, mauvaise validation des entrées… |
| Vulnérabilités des dépendances | `npm audit` (front), OWASP Dependency-Check (back), Dependency Review de GitHub | Dépendances connues vulnérables, **y compris celles que la PR ajoute ou met à jour** |
| Licences des dépendances | Dependency Review de GitHub | Licences incompatibles avec le projet |
| Détection de secrets | Gitleaks ou secret scanning de GitHub | Mots de passe, clés ou jetons commités par erreur (**exécutée aussi dès le push**, car rapide et à traiter immédiatement) |

- À l'exception de la détection de secrets, ces contrôles sont réservés aux PR plutôt qu'aux pushes : ils sont plus lents, et la PR est le moment où la décision de fusion est prise.
- Un échec de ces contrôles bloque la fusion, comme un test en échec. Les seuils de gravité (par exemple, bloquer à partir de « élevée ») seront fixés dans le plan de sécurité.
- Le détail des outils, des seuils et du traitement des vulnérabilités est donné dans la partie 2.

**d) Contrôles sur l'image Docker (principe : valider avant la fusion, publier après)**

Une fois la PR fusionnée, plus rien ne peut empêcher la fusion : l'image doit donc être vérifiée **sur la PR**, et la publication n'intervient qu'**après**. La PR exécute :

| Contrôle | PR vers `develop` | PR vers `main` | Détail et objectif |
|----------|:---:|:---:|--------------------|
| Build des images | oui | oui | Cibles `front` et `back` du `Dockerfile` : vérifier qu'il produit bien ce qui sera livré |
| Test de fumée | oui | oui | Démarrer les images `front` et `back` avec `compose.test.yml`, vérifier que la page d'accueil répond et qu'un appel à l'API aboutit (par exemple la liste des organisations) : des tests au vert ne garantissent pas que le conteneur démarre |
| Scan des images | | oui | Trivy ; seuil de gravité bloquant défini dans le plan de sécurité : détecter les vulnérabilités de l'OS et des images de base, invisibles dans le code |

- Les images de PR sont **jetables** : jamais publiées, supprimées à la fin du job.
- Le scan, plus long, est réservé aux PR vers `main` ; `main` reste la dernière barrière avant la livraison.
- Après la fusion, le workflow de publication **rejoue build et test de fumée avant le push**, car l'image est reconstruite sur le commit de fusion (partie 3, § 3.5). En cas d'échec après fusion : partie 3, § 3.8.
- Le test de fumée échoue si le conteneur ne répond pas dans un délai défini (par exemple 60 secondes).

**e) Organisation du pipeline**

- Les jobs (tests back, tests front, qualité, et sécurité sur PR) tournent **en parallèle**, car les deux applications sont indépendantes.
- Les exécutions concurrentes sur une même branche sont annulées au profit de la plus récente (`concurrency` avec `cancel-in-progress`).
- Le résultat est une **vérification obligatoire** pour fusionner une PR (protection de branche, voir plan de sécurité).

### 3.3 Fusion sur `develop` et sur `main`

- Mêmes tests qu'en § 3.2, avec mesure de la couverture.
- La promotion de `develop` vers `main` se fait **uniquement par pull request**, avec les mêmes exigences : tests au vert, relecture et validation par un relecteur.
- Le build, le test de fumée (et, pour `main`, le scan) des images s'exécutent **avant** la fusion, sur la PR (§ 3.2 d).
- Après fusion sur `main`, la CI vérifie que la branche reste livrable. Le déclenchement éventuel du déploiement est traité dans la partie 3.
- Après fusion : build, test de fumée, scan puis **publication** des images (cibles `front` et `back`), traitées dans la partie 3, § 3.5.

### 3.4 Exécutions nocturnes

- *Condition d'activation : tests e2e écrits et environnements test / pré-production déployés (phase 3, voir feuille de route). Avant cela, la nuit ne lance que la suite complète sans cache et l'audit des dépendances.*
- Objectif propre : une régression peut apparaître **sans qu'aucun commit n'ait été fait** (dépendance transitive modifiée, image de base mise à jour, test dépendant de l'horloge ou de l'ordre d'exécution).
- Pour cela, le job nocturne s'exécute **sans cache** Gradle et npm.
- Il lance les **tests end-to-end** : l'application complète (front + back, via Docker Compose) est démarrée, puis les parcours utilisateurs principaux sont rejoués (outil à choisir, par exemple Cypress ou Playwright ; aucun test e2e n'existe aujourd'hui).
- Il s'exécute **sur `develop` et sur `main`**, car ces deux branches peuvent diverger et chacune doit être vérifiée. Une workflow planifiée ne tourne que sur la branche par défaut ; le workflow utilise donc une matrice `ref: [develop, main]` qui récupère explicitement chaque branche.
- Les e2e visent l'instance déployée : l'environnement **test** pour `develop`, l'environnement de **pré-production** pour `main` (partie 3, § 4). Les e2e ne tournent jamais contre la production.
- Il lance aussi `npm audit` et OWASP Dependency-Check (ou Trivy en mode système de fichiers) : Dependency Review de GitHub ne fonctionne que sur les PR, il ne peut pas servir la nuit (détails dans le plan de sécurité).
- **En cas d'erreur** : notification de l'équipe et **création automatique d'une issue** (§ 6). Si une issue ouverte existe déjà pour la même branche, un commentaire y est ajouté au lieu d'en créer une nouvelle, afin d'éviter une issue par nuit.

### 3.5 Exécutions hebdomadaires

- Contrôles qui n'ont pas besoin d'être quotidiens : leur dérive est lente.
- Rebuild des images Docker avec `--no-cache` et `--pull` pour récupérer les correctifs des images de base.
- Revue des tests ignorés ou instables (§ 7).
- **Sauvegarde et test de restauration de la base de données** (§ 3.6).

### 3.6 Sauvegarde et test de restauration (hebdomadaire)

*Condition d'activation : base de données persistante (phase 3). Tant que la base est en mémoire, cette procédure n'est pas mise en place.*

**Objectif** : une sauvegarde n'a de valeur que si elle se restaure. On vérifie chaque semaine, non seulement qu'une sauvegarde est produite, mais qu'elle permet de reconstituer une base exploitable.

**Constat préalable sur MicroCRM** : l'application utilise HSQLDB (`runtimeOnly 'org.hsqldb:hsqldb'` dans `back/build.gradle`) sans aucune configuration `datasource` dans `application.properties`. Par défaut, Spring Boot démarre alors une base **en mémoire**, perdue à chaque arrêt, et remplie par `spring-boot-data-fixtures`. Dans cet état, il n'y a rien à sauvegarder. La procédure ci-dessous suppose donc de **rendre la base persistante** (voir « Prérequis »).

**Environnement visé** : la sauvegarde et le test de restauration s'exécutent sur la **pré-production**, qui réplique la production. Le test de restauration valide ainsi la procédure qui servirait en production, sans y toucher. La sauvegarde de la production elle-même suit la même procédure, avec des droits dédiés (à planifier une fois la production en place).

**Deux méthodes de sauvegarde avec Docker**

| | Sauvegarde du **volume** | **Dump** logique de la base |
|---|---|---|
| Principe | Archiver le contenu du volume Docker qui porte les fichiers de la base, depuis un conteneur temporaire : `docker run --rm -v <volume>:/data -v $PWD:/backup alpine tar czf /backup/db.tar.gz -C /data .` | Exporter le contenu en SQL depuis le conteneur de la base : `docker exec <conteneur> <outil de dump> > dump.sql` (par exemple `pg_dump` pour PostgreSQL) |
| Restauration | Recréer un volume vide, y extraire l'archive (`tar xzf`), puis démarrer un conteneur dessus | Démarrer une base vierge, puis réimporter le dump (`psql < dump.sql`) |
| Avantages | Simple, indépendant du type de base, copie exacte des fichiers | Cohérent même base en marche, portable entre versions, lisible et vérifiable |
| Limites | La base doit être **arrêtée** (ou mise en pause) pour garantir la cohérence des fichiers ; liée à la version et au format de la base | Dépend d'un outil de dump propre au moteur ; plus lent sur de gros volumes |

- **Recommandation** : le dump logique pour la sauvegarde hebdomadaire (cohérent sans arrêter le service), éventuellement complété par la sauvegarde du volume avant une opération risquée (migration, montée de version).
- Le choix dépend du moteur retenu (§ 8) : avec HSQLDB en mode fichier, la sauvegarde du volume base arrêtée est la voie simple ; avec PostgreSQL, le dump est la voie naturelle.

**Déroulement du job hebdomadaire**

| Étape | Action | Critère de réussite |
|-------|--------|---------------------|
| 1. Sauvegarde | Sauvegarde du volume ou dump, selon la méthode retenue ci-dessus | Fichier produit, non vide |
| 2. Protection | Chiffrement, puis stockage hors du serveur applicatif (artefact GitHub à durée limitée, ou stockage dédié) | Fichier présent et chiffré |
| 3. Restauration | Création d'une base **vierge et isolée** (conteneur éphémère), puis import de la sauvegarde | Import sans erreur |
| 4. Vérification | Démarrage de l'application sur la base restaurée ; comparaison du nombre de lignes des tables (personnes, organisations) avec la source ; appel API de lecture | Comptages identiques, API répond |
| 5. Nettoyage | Suppression de la base et des fichiers temporaires | Aucun reste |

- En cas d'échec à l'une des étapes : notification et création d'une issue, comme pour les échecs nocturnes (§ 6).
- Durée de conservation : par exemple 4 sauvegardes hebdomadaires (un mois), à confirmer.
- Le test de restauration ne touche **jamais** la base d'origine.

**Prérequis**

- Rendre la base persistante : HSQLDB en mode fichier, avec volume Docker, ou base externe (PostgreSQL par exemple, plus adaptée à de vraies données).
- Si les données ne sont que des données de démonstration rechargées au démarrage, la sauvegarde n'a pas d'utilité réelle : le cycle se limiterait à vérifier que le chargement initial fonctionne.
- Fournir au workflow un accès à la base cible via des secrets GitHub (voir plan de sécurité), avec des droits limités à la lecture pour la sauvegarde.

## 4. Mise en œuvre (comment)

Trois workflows distincts, pour séparer les responsabilités :

| Fichier | Rôle |
|---------|------|
| `.github/workflows/ci.yml` | Push sur `features/*` et `fix/*`, PR et merge sur `develop`, PR vers `main` |
| `.github/workflows/nightly.yml` | Régression nocturne |
| `.github/workflows/weekly.yml` | Contrôle hebdomadaire approfondi, dont sauvegarde et test de restauration de la base |

Pratiques communes :

- **Cache** : `actions/setup-java` (Gradle) et `actions/setup-node` (npm) avec cache activé, sauf pour les exécutions planifiées.
- **Versions figées** : JDK 17 et version de Node alignées sur celles du `Dockerfile` pour que la CI et l'image se comportent de la même façon.
- **Chrome sans interface** : Karma est lancé avec le lanceur `ChromeHeadlessNoSandbox`, déjà défini dans `front/karma.conf.js` (l'option `--no-sandbox` est nécessaire sur un runner GitHub).
- **Déclenchement manuel** : `workflow_dispatch` ajouté à chaque workflow pour relancer à la demande.
- **Permissions minimales** : `permissions: contents: read` par défaut.

## 5. Critères de réussite et seuils

| Critère | Règle |
|---------|-------|
| Tous les tests passent | Obligatoire, sinon le pipeline échoue et la PR est bloquée |
| Build back et front | Obligatoire |
| Qualité du code (lint, analyse statique, quality gate) | Obligatoire sur push et PR ; seuils appliqués au code nouveau |
| Sécurité et dépendances (SAST, audit, licences, secrets) | Obligatoire sur PR ; seuil de gravité bloquant défini dans le plan de sécurité |
| Images Docker construites (PR vers `develop` et `main`) et saines (scan Trivy, PR vers `main`) | Obligatoire : les trois cibles se construisent ; sur `main`, le scan ne dépasse pas le seuil |
| Test de fumée du conteneur (PR vers `develop` et `main`) | Obligatoire : les images `front` et `back` démarrent et répondent |
| Couverture | Outils à ajouter : JaCoCo (back) et `--code-coverage` de Karma (front) |
| Seuil de couverture | **Phase 1** : mesurer et publier sans bloquer. **Phase 2** : fixer un seuil minimal proche de la valeur mesurée, puis le relever progressivement. Une baisse de couverture sur une PR est signalée |
| Durée | Alerte si le pipeline dépasse **10 minutes sur push** et **20 minutes sur PR** (la PR cumule tests, qualité, CodeQL et audit des dépendances ; les jobs étant parallèles, la durée est celle du plus lent) |

Les chiffres exacts de seuil seront fixés après la première mesure : en choisir un maintenant serait arbitraire.

## 6. Rapports et notifications

- Les résultats de tests (JUnit XML, rapport HTML Gradle) et la couverture sont publiés comme **artefacts** du workflow (`actions/upload-artifact`), avec une durée de conservation limitée.
- Résumé des résultats dans la page du workflow (`GITHUB_STEP_SUMMARY`).
- Échec d'un pipeline sur PR : statut visible dans la PR et mail GitHub à l'auteur.
- Échec d'un pipeline sur `develop`, `main` ou planifié : notification à l'équipe (mail GitHub, ou canal de messagerie via webhook) et ouverture d'une issue pour le suivi.
- **Issue créée par la nuit** : titre type « Échec nocturne (e2e) sur `develop` – date », avec lien vers l'exécution, branche concernée et étiquette `nightly-failure`. Elle est créée par le workflow (permission `issues: write`, par exemple via `gh issue create`), et fermée une fois la cause corrigée.

## 7. Gestion des tests instables

- Un test instable (réussit ou échoue sans changement de code) est signalé par une issue dédiée dès sa détection, grâce notamment à la répétition nocturne.
- Il est corrigé ou désactivé temporairement avec un **commentaire renvoyant vers l'issue**, jamais supprimé en silence.
- Pas de relance automatique généralisée des tests en échec : elle masquerait les vrais problèmes.
- La revue hebdomadaire (§ 3.5) liste les tests désactivés pour qu'aucun ne reste oublié.

## 8. Points à valider

- Base de données : rester sur HSQLDB en mode fichier avec volume, ou passer à une base externe (PostgreSQL) ? Sans persistance, la sauvegarde hebdomadaire n'a pas de sens (§ 3.6).
- Où stocker les sauvegardes et pendant combien de temps.
- Environnements : **décision prise**, quatre environnements (développement sur le poste, test depuis `develop`, pré-production depuis `main`, production après approbation manuelle). Reste à définir l'hébergement (partie 3, § 4).
- Nombre de relecteurs requis sur une PR vers `develop` et vers `main` (un seul par défaut).
- Revue : **décision prise**, un second compte relecteur approuve les PR (un développeur ne peut pas approuver sa propre PR), y compris vers `main`.
- Possibles contrôles supplémentaires pour `main`, non retenus à ce stade : tests end-to-end, seuils de gravité plus stricts, restriction de la branche source à `develop`.
- Fuseau et horaires des exécutions planifiées.
- Choix de l'outil end-to-end.
- Outil de qualité : **décision prise**, SonarQube Cloud, complété par les linters locaux (Checkstyle, ESLint). Vérifier que l'offre gratuite couvre le dépôt (gratuite pour un dépôt public ; les dépôts privés sont soumis à des limites).
- Canal de notification (mail uniquement ou messagerie).
