# Métriques DORA et KPI

Objectif : rassembler dans un **tableau provisoire** les 4 métriques DORA et les KPI suivis de MicroCRM, avec une analyse commentée. Ce tableau sera intégré ensuite à la documentation.

Les métriques forment deux familles, selon leur source :
- **Pipeline (CI/CD)** : mesurées à partir de GitHub Actions et de SonarCloud. Elles décrivent la façon dont le code est construit, testé et livré.
- **Application (ELK)** : mesurées à partir des logs collectés par la stack Elastic. Elles décrivent le comportement de l'application en fonctionnement.

> **Statut : provisoire.** Les colonnes « Valeur » sont **à relever** : ce document fixe d'abord ce que l'on mesure, comment et avec quel objectif.

## Synthèse

| Famille | Métrique | Type | Valeur | Objectif ou repère (élite / élevé / moyen / faible pour les DORA) |
|---|---|---|---|---|
| Pipeline (CI/CD) | Fréquence de déploiement | DORA | à relever | plusieurs / jour · 1 / jour à 1 / semaine · 1 / semaine à 1 / mois · < 1 / mois |
| Pipeline (CI/CD) | Délai de mise en production (lead time) | DORA | à relever | < 1 jour · 1 jour à 1 semaine · 1 semaine à 1 mois · > 1 mois |
| Pipeline (CI/CD) | Taux d'échec des changements (CFR) | DORA | à relever | ≤ 5 % · ≤ 10 % · ≤ 15 % · > 15 % |
| Pipeline (CI/CD) | Temps de rétablissement (MTTR) | DORA | à relever | < 1 h · < 1 jour · 1 jour à 1 semaine · > 1 semaine |
| Pipeline (CI/CD) | Temps de build | KPI | à relever | < 3 min |
| Pipeline (CI/CD) | Temps des tests back / front | KPI | à relever | < 2 min chacun |
| Pipeline (CI/CD) | Qualité Sonar | KPI | à relever | gate `OK` ; couverture > 60 % (> 80 % sur le nouveau code) ; 0 bug / vulnérabilité / code smell ; duplication < 3 % |
| Application (ELK) | Fréquence des erreurs | KPI | à relever | stable ou en baisse ; toute barre `ERROR` est analysée |

## 1. Métriques du pipeline (CI/CD)

Source : API GitHub Actions (workflows `ci.yml`, `cd.yml`, `release.yml`) et API SonarCloud.

Conventions :
- **Mise en production** = image publiée dans GHCR par la CD (`cd.yml`), puis version créée par semantic-release (`release.yml`, voir [10 Release](10-release.md)). Il n'y a pas de déploiement automatisé sur un serveur.
- Seule la branche **`main`** compte pour les DORA : les RC de `develop` montrent l'activité, pas des mises en production.
- Seuls les runs `success` et `failure` comptent ; les runs annulés ou ignorés sont exclus.
- Agrégation par la **médiane** (peu de mesures, quelques valeurs extrêmes), sur **30 jours glissants** sauf mention contraire.

### 1.1 Les 4 métriques DORA

| Métrique | Ce qu'elle mesure | Formule | Données |
|---|---|---|---|
| **Fréquence de déploiement** (DF) | le rythme de livraison | nombre de mises en production ÷ période | runs `cd.yml` réussis sur `main`, releases `vX.Y.Z` publiées |
| **Délai de mise en production** (lead time) | le temps entre un changement et sa livraison | date de publication de la release − date de chaque commit livré ; médiane | commits entre deux tags, `published_at` de la release |
| **Taux d'échec des changements** (CFR) | la part des livraisons qui échouent | livraisons en échec ÷ total des livraisons × 100 | runs `cd.yml` et `release.yml` sur `main` |
| **Temps de rétablissement** (MTTR) | le temps pour revenir à une livraison réussie | fin du premier succès − début du premier échec ; médiane | runs `cd.yml` sur `main` |

### 1.2 KPI du pipeline

| KPI | Ce qu'il mesure | Formule | Données |
|---|---|---|---|
| **Temps de build** | le coût de construction du livrable | fin − début de l'étape de build ; médiane | étapes des jobs `back` et `front` de `ci.yml` |
| **Temps des tests** back / front | le coût de la validation automatique | fin − début de l'exécution des tests ; médiane | job `front` de `ci.yml`, rapports JUnit du back |
| **Qualité Sonar** | la qualité et la sécurité du code | couverture, quality gate, bugs / vulnérabilités / code smells, duplication | projets `mikedel88_microcrm_back` et `mikedel88_microcrm_front` |

## 2. Métriques de l'application (ELK)

Source : logs du conteneur back collectés par Filebeat, indexés dans Elasticsearch (`filebeat-*`) et lus dans Kibana (voir [11 Supervision ELK](11-supervision-elk.md)).

| KPI | Ce qu'il mesure | Formule | Données |
|---|---|---|---|
| **Fréquence des erreurs** | la stabilité de l'application en fonctionnement | nombre de logs `ERROR` du back ÷ nombre d'heures | champs `log.level`, `container.name`, `@timestamp` |

La stack collecte aussi les logs d'accès de Caddy (`status`, `duration`) et les métriques Metricbeat (JVM, conteneurs). Ces données sont visibles dans le tableau de bord, mais ne sont **pas suivies comme KPI** pour l'instant.

## 3. Méthode de calcul

Chaque fiche suit le même ordre : **données**, **périmètre**, **calcul**, **outil**, **limites**.

### 3.1 Fréquence de déploiement — pipeline

- **Données** : `GET /repos/MikeDel88/microcrm/actions/workflows/cd.yml/runs` (champs `conclusion`, `head_branch`, `event`, `run_started_at`) et `GET /repos/MikeDel88/microcrm/releases` (champs `published_at`, `prerelease`).
- **Périmètre** : branche `main`, `event = push`, `conclusion = success`. Pour les releases : `prerelease = false`.
- **Calcul** :
  1. compter les runs CD réussis sur la période (images publiées) ;
  2. compter les releases finales publiées sur la même période (versions livrées) ;
  3. diviser chaque nombre par la durée de la période (par jour ou par semaine).

  Le chiffre retenu pour la DF est celui des **releases finales**. Le nombre de runs CD sert de complément.
- **Outil** : `misc/ci/deployment-frequency-weekly.yml`, chaque lundi, sur 7 jours.
- **Limites** : un run relancé puis réussi ne compte qu'une fois. Le commit `chore(release)` relance la CD sans créer de version : il gonfle le nombre de runs, mais pas celui des releases.

### 3.2 Délai de mise en production (lead time) — pipeline

- **Données** : liste des commits entre le tag précédent et le tag de la version (`git log --format=%ct vA..vB`), et `published_at` de la release `vB`.
- **Périmètre** : versions finales `vX.Y.Z` de `main`. Le commit `chore(release)` est exclu.
- **Calcul** :
  1. pour chaque commit livré : délai = `published_at` de la release − date du commit ;
  2. trier les délais et prendre la médiane de la version ;
  3. sur la période, prendre la médiane des médianes de chaque version.
- **Outil** : `misc/ci/lead-time-job.yml`, à ajouter comme job à la fin de `release.yml`.
- **Limites** : avec un squash ou un rebase, la date du commit n'est pas celle du début du travail. On peut utiliser à la place la date d'ouverture de la PR (`gh pr list --state merged --json createdAt,mergedAt`).

### 3.3 Taux d'échec des changements (CFR) — pipeline

- **Données** : runs `cd.yml` et `release.yml` (champ `conclusion`) et, pour chaque run en échec, la liste de ses jobs (`GET /actions/runs/<id>/jobs`).
- **Périmètre** : branche `main`, `event = push`, runs `success` et `failure`, sur 30 jours.
- **Calcul** : deux taux sont produits, car ils ne signifient pas la même chose.

  | Taux | Numérateur | Dénominateur | Lecture |
  |---|---|---|---|
  | **Échec avant publication** | runs `cd.yml` en échec (build, scan Trivy) | runs `cd.yml` | la CD joue son rôle de filtre : rien n'atteint GHCR. Ce n'est **pas** un échec au sens DORA |
  | **Échec après publication** (CFR DORA) | runs `release.yml` en échec (job `version` ou `publish`) | runs `cd.yml` réussis | l'image est publiée, mais la version est incomplète : c'est le taux DORA |

  Taux = numérateur ÷ dénominateur × 100.
- **Outil** : `misc/ci/cfr-weekly.yml`, chaque lundi. Une issue `publish-failure` signale aussi chaque échec de publication.
- **Limites** : sur peu de runs, le taux est peu significatif (« – » s'il n'y a aucun run). 100 runs au maximum sont lus par branche.

### 3.4 Temps de rétablissement (MTTR) — pipeline

- **Données** : runs `cd.yml` (champs `conclusion`, `run_started_at`, `updated_at`).
- **Périmètre** : branche `main`, `event = push`, runs `success` et `failure`, sur 30 jours.
- **Calcul** :
  1. trier les runs par `run_started_at` ;
  2. un run `failure` **ouvre** un incident, à la date `run_started_at`. Les échecs suivants ne comptent pas comme de nouveaux incidents ;
  3. le run `success` suivant **ferme** l'incident, à la date `updated_at` ;
  4. durée de l'incident = fermeture − ouverture ; MTTR = médiane des durées.
- **Outil** : `misc/ci/mttr-weekly.yml`, chaque lundi.
- **Limites** : on mesure le rétablissement de la **publication**, pas celui d'un service en production. Sans échec sur la période, il n'y a pas de valeur, et ce n'est pas une erreur. Un incident ouvert avant le début de la fenêtre n'est pas vu.

### 3.5 Temps de build — pipeline

- **Données** : `GET /actions/runs/<id>/jobs`, champs `steps[].started_at` et `steps[].completed_at`.
- **Périmètre** : runs `ci.yml` réussis (PR et push sur `main`), sur 30 jours.
- **Calcul** :
  - front : durée de l'étape **« Build front »** (`npm run build`) ;
  - back : durée de l'étape **« Build et tests back »** (`./gradlew build`), moins la durée des tests (voir 3.6). Le back construit et teste dans une seule commande ;
  - temps de build = somme back + front ; on prend la médiane sur les runs.
- **Outil** : requête `curl` (section 5) ; durée de chaque étape dans l'onglet du run GitHub Actions.
- **Limites** : `npm ci` et l'installation de Java ne sont pas comptés dans le build. Leur poids dépend du cache npm et Gradle.

### 3.6 Temps des tests back / front — pipeline

- **Données** :
  - front : durée de l'étape **« Tests front »** (`npm run test:ci`) dans le job `front` ;
  - back : attribut `time` des fichiers JUnit `back/build/test-results/test/*.xml` (artefact `back-reports`), également affiché par le rapport « Tests back (JUnit) ».
- **Périmètre** : runs `ci.yml` réussis, sur 30 jours.
- **Calcul** : back = somme des `time` des suites de tests ; front = fin − début de l'étape. On prend la médiane sur les runs, séparément pour le back et le front.
- **Outil** : rapports « Tests back (JUnit) » et « Tests front (Karma) » de chaque run, ou requête `curl`.
- **Limites** : la durée JUnit ne compte que l'exécution des tests, sans la compilation ni le démarrage de Gradle. Côté front, l'étape inclut le démarrage de Chrome headless.

### 3.7 Qualité Sonar — pipeline

- **Données** : `GET https://sonarcloud.io/api/measures/component` (métriques `coverage`, `new_coverage`, `bugs`, `vulnerabilities`, `code_smells`, `duplicated_lines_density`) et `GET /api/qualitygates/project_status`, pour chacun des deux projets.
- **Périmètre** : branche `main`, analyse produite par le job `sonar` de `ci.yml`. Le quality gate porte sur le **nouveau code**.
- **Calcul** (fait par SonarCloud, relevé tel quel) :
  - couverture = lignes couvertes ÷ lignes à couvrir × 100. Le back est mesuré par JaCoCo, le front par Karma ;
  - duplication = lignes dupliquées ÷ lignes de code × 100 ;
  - bugs, vulnérabilités, code smells = nombre de problèmes ouverts ;
  - quality gate = `OK` ou `ERROR`. Le job `sonar` échoue si le gate est rouge.

  On relève une valeur par projet (back et front), sans les fusionner.
- **Outil** : requête `curl` (section 5) ; tableau de bord SonarCloud.
- **Limites** : la couverture globale n'est pas bloquante, seul le nouveau code l'est. Il s'agit d'une photo à la date du relevé, pas d'une médiane.

### 3.8 Fréquence des erreurs — application

- **Données** : index `filebeat-*`, champs `log.level`, `container.name`, `@timestamp`.
- **Périmètre** : conteneur back (`container.name : microcrm-back-*`), sur la période affichée dans Kibana (par défaut les dernières 24 h).
- **Calcul** :
  1. filtrer avec `container.name : microcrm-back-* and log.level : "ERROR"` ;
  2. compter les logs sur la période (panneau « Nombre d'erreurs ») ;
  3. fréquence = nombre de logs ÷ nombre d'heures de la période ; la répartition heure par heure se lit dans le panneau « Erreurs dans le temps ».
- **Outil** : tableau de bord Kibana (voir [11 Supervision ELK](11-supervision-elk.md)).
- **Limites** : le filtre `ERROR` ne voit que les **exceptions non gérées** (réponse 500 levée par Tomcat). Les 500 gérées par Spring Data REST sont loguées en `WARN`, et les 400 / 404 ne produisent aucun log. Pour compter toutes les réponses 500, il faut élargir le filtre (section 5). La valeur dépend aussi du trafic : on l'interprète en tendance, pas en absolu.

## 4. Analyse commentée

### Pipeline (CI/CD)

**Fréquence de déploiement.** Le workflow `develop` → `main` produit une RC à chaque fusion sur `develop` et une version finale à chaque fusion sur `main`. Limite : l'historique est court (première version `v1.0.0` le 16/10/2026), donc la fréquence reste à confirmer sur plusieurs semaines.

**Lead time.** La chaîne CI → CD → release est entièrement automatisée. Le délai dépend donc surtout du temps d'attente des PR avant leur fusion, et peu de la durée des pipelines. Pour le réduire, il faut faire des PR plus petites et les relire plus vite.

**Taux d'échec des changements.** Il ne faut pas le confondre avec le taux d'échec de la CI sur les PR. Ce dernier mesure la **qualité avant fusion** : la CI joue son rôle de filtre, et un taux élevé n'est pas un mauvais signe. Un échec de la CD (scan Trivy par exemple) bloque la publication, donc rien de défaillant n'atteint GHCR. Le vrai CFR au sens DORA porte sur les échecs **après** publication (`release.yml`).

**Temps de rétablissement.** Sans déploiement sur un serveur ni incident réel en production, le MTTR se calcule sur les échecs de pipeline (`cd.yml`). Il mesure donc la vitesse de correction d'un pipeline cassé, et non la reprise d'un service. Il est peu représentatif tant que le nombre d'incidents reste faible.

**Temps de build et des tests.** Ces durées fixent le temps de retour au développeur sur chaque PR. Côté front, `npm ci` pèse lourd dans la durée totale du job ; le cache npm est le premier levier.

**Qualité Sonar.** Le quality gate ne porte que sur le **nouveau code** : il bloque les régressions sans imposer de rattraper l'historique. La couverture globale n'est pas bloquante, mais elle reste l'indicateur le plus faible du projet (36,9 % au dernier relevé archivé). C'est le premier axe d'amélioration.

### Application (ELK)

**Fréquence des erreurs.** C'est la seule métrique qui observe l'application en fonctionnement, et non sa fabrication. Elle complète les DORA : un CFR à 0 % ne garantit pas une application sans erreur. Comme le filtre `ERROR` ne voit que les exceptions non gérées, une fréquence nulle ne signifie pas une absence de réponses 500. On lit donc le filtre élargi en complément.

### Pistes d'amélioration

Les conclusions chiffrées attendent le relevé des valeurs.
1. Activer les workflows préparés dans [`misc/ci`](../misc/ci) pour mesurer les DORA chaque semaine sans calcul manuel. Ils citent encore les jobs `release` et `promote` d'une ancienne version de `cd.yml` : il faut les adapter aux jobs `version` et `publish` de `release.yml`.
2. Remonter la couverture : tests des composants front et des contrôleurs back.
3. Relever les valeurs de ce tableau sur 30 jours, puis les comparer d'un relevé à l'autre.

## 5. Sources

**Pipeline (CI/CD)**

```bash
# Runs d'un workflow : conclusion, head_branch, event, run_started_at, updated_at
curl -s "https://api.github.com/repos/MikeDel88/microcrm/actions/workflows/cd.yml/runs?branch=main&event=push&per_page=100"
curl -s "https://api.github.com/repos/MikeDel88/microcrm/actions/workflows/release.yml/runs?per_page=100"
curl -s "https://api.github.com/repos/MikeDel88/microcrm/actions/workflows/ci.yml/runs?status=success&per_page=100"
# Jobs et étapes d'un run : steps[].started_at / steps[].completed_at
curl -s "https://api.github.com/repos/MikeDel88/microcrm/actions/runs/<run_id>/jobs"
# Releases publiées : published_at, prerelease
curl -s "https://api.github.com/repos/MikeDel88/microcrm/releases?per_page=100"
# Commits livrés dans une version (lead time)
git log --format=%ct vA..vB
# Qualité Sonar, pour chaque projet
for P in mikedel88_microcrm_back mikedel88_microcrm_front; do
  curl -s "https://sonarcloud.io/api/measures/component?component=$P&metricKeys=bugs,vulnerabilities,code_smells,coverage,new_coverage,duplicated_lines_density"
  curl -s "https://sonarcloud.io/api/qualitygates/project_status?projectKey=$P"
done
```

**Application (ELK)** : dans Kibana, data view `filebeat-*`.

```text
# Fréquence des erreurs (exceptions non gérées)
container.name : microcrm-back-* and log.level : "ERROR"
# Toutes les réponses 500 (exceptions gérées par Spring Data REST incluses)
container.name : microcrm-back-* and (log.level : "ERROR" or (log.level : "WARN" and error.type : *))
```
