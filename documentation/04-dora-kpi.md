# Métriques DORA et KPI

Mesures relevées sur `MikeDel88/microcrm` (API GitHub Actions, API SonarCloud, Kibana). Ici, « mise en production » = image publiée dans GHCR (pas de déploiement automatisé). Les valeurs sont agrégées par la **médiane** : peu de mesures et quelques valeurs extrêmes.

## 1. Les 4 métriques DORA

| Métrique | Formule | Valeur mesurée | Repères DORA (élite / élevé / moyen / faible) |
|---|---|---|---|
| **Fréquence de déploiement** (DF) | **nombre total de déploiements en production ÷ période** (jour, semaine, mois) | 2 runs CD `main` réussis ÷ 1 jour = **2 / jour** (+ 2 `develop`) ; 1 release `v1.0.0` | plusieurs / jour · 1 / jour à 1 / semaine · 1 / semaine à 1 / mois · < 1 / mois |
| **Délai de mise en production** (lead time) | **date de mise en production − date de début du changement** (ouverture de la PR), médiane | PR vers `main` : médiane ≈ 6 min, + CD 2 à 4,6 min ≈ **8 à 11 min** | < 1 jour · 1 jour à 1 semaine · 1 semaine à 1 mois · > 1 mois |
| **Taux d'échec des changements** (CFR) | **déploiements en échec ÷ total des déploiements × 100** | CD : 0 ÷ 4 = **0 %** (CI avant merge : 24 ÷ 62 = 39 %) | ≤ 5 % · ≤ 10 % · ≤ 15 % · > 15 % |
| **Temps de rétablissement** (MTTR) | **Σ durées de rétablissement ÷ nombre d'incidents** ; rétablissement = fin du premier succès − début du premier échec | médiane de 15 rétablissements (runs CI) = **18 min** | < 1 h · < 1 jour · 1 jour à 1 semaine · > 1 semaine |

Lecture :
- Aucun incident de publication enregistré (l'issue `publish-failure` n'a jamais été créée).
- Les 39 % d'échecs de la CI mesurent la **qualité avant merge** : la CI joue son rôle de filtre. Ils viennent surtout de la mise en place du pipeline (nombreuses itérations en une journée).
- Limites : une seule journée d'historique pour la fréquence ; MTTR calculé sur la CI faute d'incident réel ; relevé antérieur au passage de la CI en « PR uniquement » et au scan avant push (à recalculer).

## 2. KPI suivis

| KPI | Formule | Valeur actuelle | Objectif |
|---|---|---|---|
| **Temps de build** (job `build`) | fin du job − début du job, médiane sur n runs | 92 s (back 46 s, front 30 s) | < 3 min |
| **Temps des tests** back / front (jobs `back-tests`, `front-tests`) | fin du job − début du job, médiane | 65 s / 61 s (dont `npm ci` 30 s) | < 2 min chacun |
| **Qualité SonarQube** : couverture | lignes couvertes ÷ lignes à couvrir × 100 | 36,9 % | > 60 %, > 80 % sur le nouveau code |
| **Qualité SonarQube** : bugs / vulnérabilités / code smells (nouveau code) | comptage | 0 / 0 / 0 | 0 / 0 / 0 |
| **Qualité SonarQube** : duplication (nouveau code) | lignes dupliquées ÷ lignes de code × 100 | 0,0 % | < 3 % |
| **Qualité SonarQube** : quality gate, hotspots revus | statut `OK` / `ERROR` ; revus ÷ total × 100 | OK sur les PR récentes ; 100 % | OK (bloquant) ; 100 % |
| **Fréquence des erreurs** | nombre de logs `ERROR` du back ÷ nombre d'heures | à relever dans Kibana | stable ou à la baisse |

Les temps sont mesurés sur 6 runs CI réussis de PR. Les valeurs Sonar viennent de l'ancien projet unique `MikeDel88_microcrm` ; les prochains relevés se feront sur `mikedel88_microcrm_back` et `mikedel88_microcrm_front`. Le quality gate ne porte que sur le nouveau code : la couverture globale n'est pas bloquante.

## 3. Sources

```bash
# Runs CI/CD : durée = updated_at − run_started_at ; seuls success et failure comptent
curl -s "https://api.github.com/repos/MikeDel88/microcrm/actions/runs?per_page=100"
# Durée des jobs d'un run : completed_at − started_at
curl -s "https://api.github.com/repos/MikeDel88/microcrm/actions/runs/<run_id>/jobs"
# Lead time : merged_at − created_at des PR fusionnées
curl -s "https://api.github.com/repos/MikeDel88/microcrm/pulls?state=closed&per_page=100"
# Qualité Sonar, pour chaque projet
for P in mikedel88_microcrm_back mikedel88_microcrm_front; do
  curl -s "https://sonarcloud.io/api/measures/component?component=$P&metricKeys=bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density"
  curl -s "https://sonarcloud.io/api/qualitygates/project_status?projectKey=$P"
done
```

Fréquence des erreurs, dans Kibana : data view `filebeat-*`, filtre `container.name : microcrm-back-* and log.level : "ERROR"`, histogramme par heure (voir [03](03-supervision-elk.md)).

Ce que compte ce filtre (vérifié le 26/10/2026) :

| Cas | Réponse | Niveau de log |
|---|---|---|
| Exception non gérée (ex. `DELETE /organizations/1`) | 500 | **ERROR** (Tomcat, avec `error.type` et `error.stack_trace`) |
| Exception gérée par Spring Data REST (ex. `GET /persons/abc`) | 500 | **WARN** (`RepositoryRestExceptionHandler`, avec `error.type`) |
| JSON invalide, ressource absente | 400, 404 | aucun log |

Le filtre `ERROR` ne voit donc que les exceptions non gérées. Pour compter toutes les réponses 500 : `container.name : microcrm-back-* and (log.level : "ERROR" or (log.level : "WARN" and error.type : *))`.

## 4. Automatiser la mesure

Quatre workflows sont préparés dans `misc/ci/`, **non actifs** (hors de `.github/workflows/`, jamais exécutés) :

| Métrique | Fichier | Fréquence | Calcul |
|---|---|---|---|
| Lead time | `lead-time-job.yml` (job à ajouter à `cd.yml`) | À chaque release | Fin de `promote` − date de chaque commit livré ; médiane |
| Fréquence de déploiement | `deployment-frequency-weekly.yml` | Chaque lundi | Runs `cd.yml` réussis par branche et releases publiées sur 7 jours |
| MTTR | `mttr-weekly.yml` | Chaque lundi | Sur 30 jours, runs `cd.yml` : premier échec → succès suivant ; médiane |
| Taux d'échec | `cfr-weekly.yml` | Chaque lundi | Sur 30 jours : échecs de pipeline, et échecs après publication (`release` / `promote`, le taux DORA) |

Activation : copier les workflows dans `.github/workflows/` et fusionner sur `main` (un workflow planifié ne tourne que depuis la branche par défaut). Aucun secret requis.

## 5. Suite recommandée

1. Vérifier après le prochain merge sur `main` que les deux projets Sonar affichent couverture et quality gate.
2. Remonter la couverture : tests des composants front et des contrôleurs back.
3. Activer les workflows de mesure et suivre l'évolution semaine après semaine.
