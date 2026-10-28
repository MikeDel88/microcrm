# Métriques DORA et KPI

Objectif : rassembler dans un **tableau provisoire** les 4 métriques DORA et les KPI suivis de MicroCRM, avec une analyse commentée. Ce tableau sera intégré ensuite à la documentation.

Les métriques forment deux familles, selon leur source :
- **Pipeline (CI/CD)** : mesurées à partir de GitHub Actions et de SonarCloud. Elles décrivent la façon dont le code est construit, testé et livré.
- **Application (ELK)** : mesurées à partir des logs collectés par la stack Elastic. Elles décrivent le comportement de l'application en fonctionnement.

> **Statut : provisoire.** Premier relevé du **27/10/2026**, sur un historique court (première version le 16/10/2026). Deux valeurs restent à consolider : le temps des tests back (relevé local, à confirmer en CI) et la fréquence des erreurs (non représentative tant que l'application n'est pas en production).

## Synthèse

| Famille | Métrique | Type | Valeur | Objectif ou repère (élite / élevé / moyen / faible pour les DORA) |
|---|---|---|---|---|
| Pipeline (CI/CD) | Fréquence de déploiement | DORA | **0,36 / jour** (4 releases en 11 jours, 16/10 → 27/10/2026) ≈ 2,5 / semaine : niveau **élevé** ; CD réussies : 7 (0,64 / jour). Données : [`metriques/dora/releases.json`](metriques/dora/releases.json), [`metriques/dora/runs_cd.json`](metriques/dora/runs_cd.json) | plusieurs / jour · 1 / jour à 1 / semaine · 1 / semaine à 1 / mois · < 1 / mois |
| Pipeline (CI/CD) | Délai de mise en production (lead time) | DORA | **≈ 45 h** (1,9 jour), médiane des médianes des 4 releases (v1.0.0 : 44,5 h · v1.1.0 : 70,1 h · v1.1.1 : 46,2 h · v1.1.2 : 1,2 h) : niveau **élevé**. Données : `git log` entre les tags, [`metriques/dora/releases.json`](metriques/dora/releases.json) | < 1 jour · 1 jour à 1 semaine · 1 semaine à 1 mois · > 1 mois |
| Pipeline (CI/CD) | Taux d'échec des changements (CFR) | DORA | **0 %** (0 échec après publication sur 7 mises en production `main`, 16/10 → 27/10/2026) : niveau **élite**. Hors CFR : 1 échec avant publication sur `develop` (1 / 12 = 8,3 %, issue #38). Données : API GitHub, runs `cd.yml` et `release.yml` | ≤ 5 % · ≤ 10 % · ≤ 15 % · > 15 % |
| Pipeline (CI/CD) | Temps de rétablissement (MTTR) | DORA | **non mesurable** sur `main` : aucun incident du 16/10 au 27/10/2026 (0 ÷ 0, ce n'est pas 0). Pour information : 1 incident sur `develop` (issue #38), rétabli en **19 min**, sous le seuil élite (< 1 h). Données : API GitHub, runs `cd.yml` | < 1 h · < 1 jour · 1 jour à 1 semaine · > 1 semaine |
| Pipeline (CI/CD) | Temps de build | KPI | **37 s** (médiane sur les 5 runs CI réussis depuis la refonte du 26/10 : back 30 s, tests back inclus, + front 7 s) : objectif **atteint**. Run CI complet : 152 s (≈ 2,5 min). Données : API GitHub, jobs des runs `ci.yml` ; liste des runs dans [`metriques/kpi/build.json`](metriques/kpi/build.json) | < 3 min |
| Pipeline (CI/CD) | Temps des tests back / front | KPI | **back ≈ 1 s** d'exécution JUnit (relevé local du 26/10, **à confirmer en CI**) / **front 18 s** (médiane sur les 5 runs CI depuis le 26/10) : objectif **atteint**. Données : rapports JUnit `back/build/test-results`, API GitHub (étape « Tests front », runs de [`metriques/kpi/build.json`](metriques/kpi/build.json)) | < 2 min chacun |
| Pipeline (CI/CD) | Qualité Sonar | KPI | **Quality gate `OK`** (back et front, analyse du 27/10/2026). Code global : couverture **56,4 %** (back) / **26,4 %** (front) ; bugs 0 / 20 ; vulnérabilités 3 / 1 ; code smells 7 / 16 ; duplication 9,1 % / 0,0 %. Objectif **partiellement atteint** : le gate passe, mais la couverture et la dette héritée restent hors objectif. Données : API SonarCloud | gate `OK` ; couverture > 60 % (> 80 % sur le nouveau code) ; 0 bug / vulnérabilité / code smell ; duplication < 3 % |
| Application (ELK) | Fréquence des erreurs | KPI | **Non représentative à ce jour** : l'application n'est pas en production, elle ne tourne qu'en local lors des tests manuels. Il n'y a pas de trafic réel, donc le nombre d'erreurs dépend uniquement des requêtes envoyées à la main. La chaîne de mesure (Filebeat → Elasticsearch → Kibana) est en place ; le KPI sera relevé une fois l'application en production | stable ou en baisse ; toute barre `ERROR` est analysée |

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
- **Outil** : requêtes `curl` sur l'API GitHub (section 5), réponses enregistrées dans [`metriques/dora/`](metriques/dora/).
- **Relevé du 27/10/2026** : réponses JSON de l'API GitHub enregistrées dans le répertoire [`metriques/dora/`](metriques/dora/) :
  - [`metriques/dora/runs_cd.json`](metriques/dora/runs_cd.json) : `https://api.github.com/repos/MikeDel88/microcrm/actions/workflows/cd.yml/runs?branch=main&event=push&status=success`. Il donne `total_count` = 7, avec des runs du 16/10 au 27/10 ;
  - [`metriques/dora/releases.json`](metriques/dora/releases.json) : `https://api.github.com/repos/MikeDel88/microcrm/releases`. Il contient 4 releases finales (`v1.0.0` à `v1.1.2`, `prerelease = false`, `draft = false`) ;
  - calcul : 4 releases ÷ 11 jours = 0,36 / jour ≈ 2,5 / semaine ; 7 runs CD ÷ 11 jours = 0,64 / jour.
- **Limites** : un run relancé puis réussi ne compte qu'une fois. Le commit `chore(release)` relance la CD sans créer de version : il gonfle le nombre de runs, mais pas celui des releases.

### 3.2 Délai de mise en production (lead time) — pipeline

- **Données** : liste des commits entre le tag précédent et le tag de la version (`git log --no-merges --format='%h %aI %s' vA..vB`), et `published_at` de la release `vB`.
- **Périmètre** : versions finales `vX.Y.Z` de `main`. Sont exclus :
  - les commits de merge, dont la date est celle de la fusion et non celle du travail ;
  - les commits `chore(release)`, créés par semantic-release ;
  - pour `v1.0.0`, les 2 commits du projet de départ (« Initial commit » et « microcrm app », 12/2025 et 01/2026), qui ajouteraient près de 10 mois.
- **Calcul** :
  1. pour chaque commit livré : délai = `published_at` de la release − date d'auteur du commit (`%aI`, qui ne change pas lors d'un rebase), les deux en UTC ;
  2. trier les délais et prendre la médiane de la version ;
  3. sur la période, prendre la médiane des médianes de chaque version.
- **Outil** : `git log` entre les tags (section 5) ; dates de publication dans [`metriques/dora/releases.json`](metriques/dora/releases.json).
- **Relevé du 27/10/2026** : commits lus avec `git log` entre les tags, dates de publication tirées de [`metriques/dora/releases.json`](metriques/dora/releases.json).

  | Release | Publiée (UTC) | Commits livrés | Médiane | Min | Max |
  |---|---|---|---|---|---|
  | v1.0.0 | 16/10 10:13 | 55 | 44,5 h | 0,3 h | 96,3 h |
  | v1.1.0 | 22/10 14:00 | 11 | 70,1 h | 0,2 h | 145,3 h |
  | v1.1.1 | 26/10 10:35 | 4 | 46,2 h | 0,3 h | 91,3 h |
  | v1.1.2 | 26/10 11:43 | 1 | 1,2 h | 1,2 h | 1,2 h |

  Médiane des médianes = (44,5 + 46,2) ÷ 2 = **45,4 h ≈ 1,9 jour**. La médiane sur les 71 commits pris ensemble donne 44,5 h, soit un résultat quasi identique.
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

  Pour attribuer un run `release.yml` en échec à une branche :
  - job `publish` (déclenché par le push d'un tag) : `vX.Y.Z` correspond à `main`, `vX.Y.Z-rc.N` à `develop` ;
  - job `version` (déclenché par `workflow_run`) : GitHub renseigne `head_branch` et `head_sha` avec la branche par défaut (`main`), et non avec la CD qui a déclenché le run. On retrouve donc la CD qui s'est terminée juste avant le début du run (environ 2 s d'écart en pratique, moins de 2 min retenues) et on reprend sa branche.
- **Outil** : requêtes `curl` sur l'API GitHub (section 5). Une issue `publish-failure` signale aussi chaque échec de la CD.
- **Relevé du 27/10/2026** : API GitHub, `https://api.github.com/repos/MikeDel88/microcrm/actions/workflows/cd.yml/runs?per_page=100` et `.../workflows/release.yml/runs?per_page=100`.

  | Branche | Runs `cd.yml` | Échecs avant publication | Taux | Échecs après publication | CFR DORA |
  |---|---|---|---|---|---|
  | `main` | 7 | 0 | 0 % | 0 | **0 %** |
  | `develop` | 12 | 1 (run #14, 26/10 14:51, issue #38) | 8,3 % | 0 | 0 % |

  - `release.yml` n'existe que depuis le 26/10 (5 runs, tous réussis). Les releases v1.0.0 à v1.1.1 ont été produites par les anciens jobs `release` et `promote` de `cd.yml` : comme les 7 runs `cd.yml` sur `main` ont tous réussi, ces versions n'ont pas eu d'échec après publication non plus.
  - CFR = 0 ÷ 7 × 100 = **0 %**. L'échec sur `develop` ne compte pas : il s'est produit avant la publication, sur une branche qui ne livre que des RC.
- **Limites** : sur peu de runs, le taux est peu significatif (« – » s'il n'y a aucun run). Avec 7 mises en production, un seul échec ferait passer le CFR à 12,5 % (niveau moyen). 100 runs au maximum sont lus par branche.

### 3.4 Temps de rétablissement (MTTR) — pipeline

- **Données** : runs `cd.yml` (champs `conclusion`, `run_started_at`, `updated_at`).
- **Périmètre** : branche `main`, `event = push`, runs `success` et `failure`, sur 30 jours.
- **Calcul** :
  1. trier les runs par `run_started_at` ;
  2. un run `failure` **ouvre** un incident, à la date `run_started_at`. Les échecs suivants ne comptent pas comme de nouveaux incidents ;
  3. le run `success` suivant **ferme** l'incident, à la date `updated_at` ;
  4. durée de l'incident = fermeture − ouverture ; MTTR = médiane des durées.
- **Outil** : requêtes `curl` sur l'API GitHub (section 5) ; les issues `publish-failure` aident à repérer les incidents.
- **Relevé du 27/10/2026** : API GitHub, `https://api.github.com/repos/MikeDel88/microcrm/actions/workflows/cd.yml/runs?per_page=100`.
  - `main` : 7 runs, tous `success`. Il n'y a aucun incident, donc **aucune durée à mesurer** : le MTTR est non mesurable. Écrire « 0 » signifierait que les incidents ont été corrigés instantanément, ce qui n'est pas le cas.
  - `develop` : un seul incident, présenté pour information.

    | Run | Résultat | Début | Fin |
    |---|---|---|---|
    | #14 | `failure`, ouvre l'incident (issue #38) | 26/10 14:51:38Z | 14:54:28Z |
    | #15 | `success`, ferme l'incident | 15:09:28Z | 15:10:50Z |

    Rétablissement = 15:10:50 − 14:51:38 = **19 min**. Cet incident montre que la boucle détection (issue automatique), correction et relance fonctionne. Mais il repose sur un seul cas, sur une branche de RC, avant publication : ce n'est pas un MTTR DORA au sens strict.
- **Limites** : on mesure le rétablissement de la **publication**, pas celui d'un service en production. Sans échec sur la période, il n'y a pas de valeur, et ce n'est pas une erreur. Un incident ouvert avant le début de la fenêtre n'est pas vu.

### 3.5 Temps de build — pipeline

- **Données** : `GET /actions/runs/<id>/jobs`, champs `steps[].started_at` et `steps[].completed_at`.
- **Périmètre** : runs `ci.yml` réussis (PR et push sur `main`), sur 30 jours.
- **Calcul** :
  - front : durée de l'étape **« Build front »** (`npm run build`) ;
  - back : durée de l'étape **« Build et tests back »** (`./gradlew build`). Le back construit et teste dans une seule commande, et l'API ne donne pas la durée des tests (le rapport « Tests back (JUnit) » n'indique que le nombre de tests). La valeur retenue **inclut donc les tests back**. Pour les retirer, il faut lire leur durée dans l'artefact `back-reports` (`build/reports/tests/test/index.html`) ;
  - temps de build = somme back + front ; on prend la médiane sur les runs.
- **Outil** : requête `curl` (section 5) ; durée de chaque étape dans l'onglet du run GitHub Actions.
- **Relevé du 27/10/2026** : API GitHub, `https://api.github.com/repos/MikeDel88/microcrm/actions/workflows/ci.yml/runs?status=success&per_page=10`, puis `.../actions/runs/<id>/jobs` pour chaque run. La liste des runs CI réussis (52 au 27/10/2026) est enregistrée dans [`metriques/kpi/build.json`](metriques/kpi/build.json).

  Seuls les runs **#80 à #87** sont retenus : ils utilisent le `ci.yml` actuel (jobs `back`, `front`, `sonar`). Les runs précédents (#69 à #75) utilisaient l'ancien pipeline (jobs `build`, `back-tests`, `front-tests`, `codeql`, `linter-*`…), dont les étapes ne mesurent pas la même chose.

  | Run | Événement | Date (UTC) | Build et tests back | Build front | `npm ci` | Run complet |
  |---|---|---|---|---|---|---|
  | #87 | push | 27/10 10:20 | 24 s | 8 s | 10 s | 112 s |
  | #86 | PR | 27/10 09:47 | 22 s | 5 s | 6 s | 152 s |
  | #85 | PR | 27/10 09:34 | 30 s | 9 s | 11 s | 146 s |
  | #81 | PR | 26/10 15:17 | 49 s | 7 s | 28 s | 156 s |
  | #80 | PR | 26/10 15:04 | 31 s | 7 s | 8 s | 208 s |
  | **Médiane** | | | **30 s** | **7 s** | **10 s** | **152 s** |

  Temps de build = 30 + 7 = **37 s**, très en dessous de l'objectif de 3 min. La valeur est légèrement surestimée, car elle inclut les 2 tests back. Le run complet (back, front, Sonar et attente du quality gate) dure 152 s en médiane : c'est l'attente réelle du développeur sur une PR, et Sonar en est la plus grosse part (≈ 86 s).
- **Limites** : `npm ci` et l'installation de Java ne sont pas comptés dans le build. Leur poids dépend du cache npm et Gradle : le run #81, le plus lent (49 s pour le back), coïncide avec le `npm ci` le plus long (28 s), sans doute un cache vide ou un runner chargé. Les durées sont arrondies à la seconde. Il n'y a que 5 runs comparables depuis la refonte de la CI, donc la médiane est à reconfirmer.

### 3.6 Temps des tests back / front — pipeline

- **Données** :
  - front : durée de l'étape **« Tests front »** (`npm run test:ci`) dans le job `front` ;
  - back : attribut `time` des balises `<testsuite>` des fichiers JUnit `back/build/test-results/test/*.xml`, ou case *duration* de `build/reports/tests/test/index.html`. En CI, ces fichiers sont dans l'artefact **`back-reports`** de chaque run (téléchargement depuis la page du run, connexion requise). L'API ne donne pas cette durée : le rapport « Tests back (JUnit) » n'indique que le nombre de tests, et ses dates de début et de fin sont identiques.
- **Périmètre** : runs `ci.yml` réussis, sur 30 jours.
- **Calcul** : back = somme des `time` des suites de tests ; front = fin − début de l'étape. On prend la médiane sur les runs, séparément pour le back et le front.
- **Outil** : API GitHub pour le front (étape « Tests front », comme en 3.5) ; artefact `back-reports` pour le back.
- **Relevé du 27/10/2026** :
  - front : étape « Tests front » des 5 runs du `ci.yml` actuel (#80 à #87, voir 3.5) : 18, 18, 14, 13, 20 s, soit une **médiane de 18 s** ;
  - back : relevé **local** du 26/10 (`back/build/test-results/test/`), en attendant les artefacts CI.

    | Classe de test | Tests | `time` |
    |---|---|---|
    | `MicroCRMApplicationTests` | 1 | 0,851 s |
    | `PersonRepositoryIntegrationTest` | 1 | 0,102 s |
    | **Total** | 2 | **≈ 1 s** |

    À confirmer en CI : télécharger l'artefact `back-reports` des runs #80 à #87 et prendre la médiane. Sur un runner GitHub, on peut s'attendre à quelques secondes.
- **Limites** : la durée JUnit ne compte que l'exécution des tests. Elle laisse de côté le démarrage de la JVM de test et une partie du chargement du contexte Spring, souvent les plus longs. Le coût réel des tests back pour le développeur se situe donc entre la durée JUnit (≈ 1 s) et l'étape complète « Build et tests back » (30 s, voir 3.5). Côté front, l'étape inclut le démarrage de Chrome headless. Avec 2 tests back et 8 tests front, ces durées restent faibles : elles augmenteront avec la couverture.

### 3.7 Qualité Sonar — pipeline

- **Données** : `GET https://sonarcloud.io/api/measures/component` (métriques `coverage`, `new_coverage`, `bugs`, `vulnerabilities`, `code_smells`, `duplicated_lines_density`) et `GET /api/qualitygates/project_status`, pour chacun des deux projets.
- **Périmètre** : branche `main`, analyse produite par le job `sonar` de `ci.yml`. Le quality gate porte sur le **nouveau code**.
- **Calcul** (fait par SonarCloud, relevé tel quel) :
  - couverture = (conditions couvertes + lignes couvertes) ÷ (2 × conditions + lignes à couvrir) × 100. Sonar combine les lignes et les branches (`if` / `else`) : la valeur est donc un peu différente du simple rapport lignes couvertes ÷ lignes à couvrir. Le back est mesuré par JaCoCo, le front par Karma ;
  - duplication = lignes dupliquées ÷ lignes de code × 100 ;
  - bugs, vulnérabilités, code smells = nombre de problèmes ouverts ;
  - quality gate = `OK` ou `ERROR`. Le job `sonar` échoue si le gate est rouge.

  On relève une valeur par projet (back et front), sans les fusionner.
- **Outil** : requête `curl` (section 5) ; tableau de bord SonarCloud. L'API est publique pour les deux projets, aucun jeton n'est nécessaire.
- **Relevé du 27/10/2026** : dernières analyses sur `main`, à 10:21 (back) et 10:22 (front), produites par le run CI #87.

  **Quality gate (nouveau code)** : c'est lui qui bloque la CI.

  | Condition | Seuil | Back | Front |
  |---|---|---|---|
  | Notes fiabilité / sécurité / maintenabilité | A | A | A |
  | Duplication sur le nouveau code | ≤ 3 % | 0,0 % | 0,0 % |
  | Security hotspots revus | 100 % | 100 % | 100 % |
  | Couverture du nouveau code | ≥ 80 % | – | 25,0 % (condition ignorée, voir ci-dessous) |
  | **Statut** | | **OK** | **OK** |

  **Code global** : ce que le gate ne bloque pas.

  | Mesure | Back | Front | Objectif |
  |---|---|---|---|
  | Couverture | 56,4 % (28 lignes non couvertes sur 70) | 26,4 % (87 sur 123) | > 60 % |
  | Bugs | 0 | 20 | 0 |
  | Vulnérabilités | 3 | 1 | 0 |
  | Code smells | 7 | 16 | 0 |
  | Duplication | 9,1 % | 0,0 % | < 3 % |
  | Lignes de code | 226 | 749 | – |

- **Limites** :
  - la couverture globale n'est pas bloquante, seul le nouveau code l'est. Le gate peut donc être vert alors que le code hérité du projet de départ porte des bugs et des vulnérabilités : c'est la stratégie *clean as you code* ;
  - Sonar ignore les conditions de couverture et de duplication quand le nouveau code est très petit (moins de 20 lignes à couvrir). C'est pourquoi la couverture du nouveau code front (25 %) n'a pas fait échouer le gate ;
  - il s'agit d'une photo à la date du relevé, pas d'une médiane.

### 3.8 Fréquence des erreurs — application

- **Données** : index `filebeat-*`, champs `log.level`, `container.name`, `@timestamp`.
- **Périmètre** : conteneur back (`container.name : microcrm-back-*`), sur la période affichée dans Kibana (par défaut les dernières 24 h).
- **Calcul** :
  1. filtrer avec `container.name : microcrm-back-* and log.level : "ERROR"` ;
  2. compter les logs sur la période (panneau « Nombre d'erreurs ») ;
  3. fréquence = nombre de logs ÷ nombre d'heures de la période ; la répartition heure par heure se lit dans le panneau « Erreurs dans le temps ».
- **Outil** : tableau de bord Kibana (voir [11 Supervision ELK](11-supervision-elk.md)). Le panneau « Nombre d'erreurs » filtre sur `log.level : "ERROR"` sans `container.name` : pour le KPI, il faut utiliser la requête complète de l'étape 1.
- **Relevé du 27/10/2026** : **non relevé, car non représentatif**. MicroCRM n'est pas déployé en production : l'application et la stack ELK ne tournent qu'en local, pendant les sessions de développement et de test. Les logs viennent donc des requêtes envoyées à la main, et pas d'utilisateurs. Une valeur, même nulle, ne dirait rien de la stabilité de l'application : « 0 erreur » sans trafic ne prouve rien, et les erreurs provoquées volontairement (scénario de [11 Supervision ELK](11-supervision-elk.md), « Générer des logs ») ne sont pas des incidents.

  Ce qui est vérifié aujourd'hui, c'est la **chaîne de mesure**. Le scénario de test produit 1 log `ERROR` (`DELETE /organizations/1`) et 1 `WARN` avec `error.type` (`GET /persons/abc`), visibles dans Kibana avec les filtres ci-dessus. Le KPI sera relevé dès qu'il y aura un environnement avec du trafic réel (production, ou préproduction avec un trafic de référence).
- **Limites** : le filtre `ERROR` ne voit que les **exceptions non gérées** (réponse 500 levée par Tomcat). Les 500 gérées par Spring Data REST sont loguées en `WARN`, et les 400 / 404 ne produisent aucun log. Pour compter toutes les réponses 500, il faut élargir le filtre (section 5). La valeur dépend aussi du trafic : on l'interprète en tendance, pas en absolu.

## 4. Analyse commentée

### Pipeline (CI/CD)

**Fréquence de déploiement.** Le workflow `develop` → `main` produit une RC à chaque fusion sur `develop` et une version finale à chaque fusion sur `main`. Limite : l'historique est court (première version `v1.0.0` le 16/10/2026), donc la fréquence reste à confirmer sur plusieurs semaines.

**Lead time.** La chaîne CI → CD → release est entièrement automatisée. Le délai dépend donc surtout du temps d'attente des PR avant leur fusion, et peu de la durée des pipelines. Le relevé le confirme : les commits attendent sur `develop` avant la fusion sur `main` (jusqu'à 6 jours pour v1.1.0), alors que le correctif seul de v1.1.2 a été livré en 1,2 h. Pour réduire le délai, il faut faire des PR plus petites et les fusionner plus souvent sur `main`.

**Taux d'échec des changements.** Il ne faut pas le confondre avec le taux d'échec de la CI sur les PR. Ce dernier mesure la **qualité avant fusion** : la CI joue son rôle de filtre, et un taux élevé n'est pas un mauvais signe. Un échec de la CD (scan Trivy par exemple) bloque la publication, donc rien de défaillant n'atteint GHCR. Le vrai CFR au sens DORA porte sur les échecs **après** publication (`release.yml`).

**Temps de rétablissement.** Sans déploiement sur un serveur ni incident réel en production, le MTTR se calcule sur les échecs de pipeline (`cd.yml`). Il mesure donc la vitesse de correction d'un pipeline cassé, et non la reprise d'un service. Il est peu représentatif tant que le nombre d'incidents reste faible.

**Temps de build et des tests.** Ces durées fixent le temps de retour au développeur sur chaque PR. Côté front, `npm ci` pèse lourd dans la durée totale du job ; le cache npm est le premier levier.

**Qualité Sonar.** Le quality gate ne porte que sur le **nouveau code** : il bloque les régressions sans imposer de rattraper l'historique. La couverture globale n'est pas bloquante, mais elle reste l'indicateur le plus faible du projet : 56,4 % pour le back et 26,4 % pour le front, sous l'objectif de 60 %. Le front porte aussi l'essentiel de la dette héritée (20 bugs, 16 code smells), et le back 3 vulnérabilités et 9,1 % de duplication. Remonter la couverture du front est le premier axe d'amélioration, puis traiter les vulnérabilités.

### Application (ELK)

**Fréquence des erreurs.** C'est la seule métrique qui observe l'application en fonctionnement, et non sa fabrication. Elle complète les DORA : un CFR à 0 % ne garantit pas une application sans erreur. Comme le filtre `ERROR` ne voit que les exceptions non gérées, une fréquence nulle ne signifie pas une absence de réponses 500. On lit donc le filtre élargi en complément.

À ce jour, cette métrique n'est **pas représentative** : sans production ni trafic réel, le nombre d'erreurs reflète les manipulations faites en local, pas le comportement de l'application face à ses utilisateurs. La supervision est prête (collecte, filtres, tableau de bord). Il manque l'environnement à superviser : c'est la limite principale de la partie application de ce tableau.

### Pistes d'amélioration

1. Automatiser la mesure : un workflow planifié qui lit l'API GitHub (section 5) éviterait le calcul manuel des DORA, du temps de build et du temps des tests.
2. Remonter la couverture : tests des composants front et des contrôleurs back.
3. Relever les valeurs de ce tableau sur 30 jours, puis les comparer d'un relevé à l'autre.


**Application (ELK)** : dans Kibana, data view `filebeat-*`.

```text
# Fréquence des erreurs (exceptions non gérées)
container.name : microcrm-back-* and log.level : "ERROR"
# Toutes les réponses 500 (exceptions gérées par Spring Data REST incluses)
container.name : microcrm-back-* and (log.level : "ERROR" or (log.level : "WARN" and error.type : *))
```
