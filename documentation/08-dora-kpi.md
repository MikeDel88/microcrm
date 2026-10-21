# 08 - Métriques DORA et KPI opérationnels

Mesures relevées sur `MikeDel88/microcrm` (API GitHub Actions, API publique SonarCloud, historique git).

## 1. Les 4 métriques DORA

| Métrique | Définition retenue | Valeur mesurée | Niveau DORA indicatif |
|---|---|---|---|
| **Fréquence de déploiement** | Push réussis sur `main` (images publiées dans GHCR) par jour | 2 déploiements `main` + 2 `develop` (SNAPSHOT) le 16/10 ; 1 release (`v1.0.0`) | Élevé (≥ 1/jour), mais sur 1 seul jour d'activité |
| **Délai de mise en production** (lead time) | Ouverture de la PR vers `main` -> merge, + durée du run CD | PR vers `main` : 2,8 h, 0,1 h, 0,1 h, 0,1 h (médiane ≈ 6 min) ; CD `main` : 120 à 278 s | Élevé (< 1 jour) |
| **Taux d'échec des changements** | Déploiements `main` en échec / déploiements `main` | CD : 0 échec sur 4 runs (0 %). CI avant merge : 24 échecs sur 62 runs (39 %) | 0 % en production ; la CI joue son rôle de filtre |
| **Temps de rétablissement** (MTTR) | Durée entre un run CI en échec et le run suivant au vert | Médiane 18 min (15 rétablissements) | Élevé (< 1 h) |

Lecture : aucun incident de production n'est enregistré (l'issue `publish-failure` créée par `notify-failure` n'a jamais été déclenchée). Le taux d'échec de 39 % de la CI est une mesure de **qualité avant merge**, pas un échec de production ; il s'explique surtout par la mise en place du pipeline (nombreuses PR `feature/ci` en 1 journée, avec des itérations sur la config).

Limites : le MTTR est un proxy (pas d'incident de production réel) ; la fréquence de déploiement n'a qu'une journée d'historique.

Évolution du pipeline depuis ce relevé : (1) la CI ne tourne plus sur les push de branche mais uniquement sur PR, ce qui supprime les runs en double ; le taux de réussite et le MTTR de la CI, calculés sur les anciens runs push + PR, sont à recalculer. (2) La CD scanne l'image avant de la pousser (build local, Trivy, puis push) : les durées de CD ci-dessous précèdent ce changement et seront un peu plus longues (scan, et second build servi par le cache).

## 2. KPI opérationnels

### Pipeline (mesurés sur 6 runs CI réussis de PR, avant l'ajout du scan Trivy dans le job `build` de la CD)

| KPI | Valeur actuelle (médiane) | Objectif |
|---|---|---|
| Durée totale d'un run CI (wall-clock) | 127 s (47 à 194 s) | < 5 min |
| Durée d'un run CD | 154 s (40 à 278 s) | < 5 min |
| Temps de build (job `build`) | 92 s (back 46 s, front 30 s) | < 3 min |
| Temps des tests back | 65 s | < 2 min |
| Temps des tests front | 61 s (dont `npm ci` 30 s, tests 25 s) | < 2 min |
| Lint back / front | 55 s / 44 s | < 1,5 min |
| Analyse Sonar | 51 s | < 2 min |
| Build image + stack (`buildx`) | 122 s | < 3 min |
| CodeQL Java / JS | 158 s / 56 s | < 4 min |
| Taux de réussite de la CI | 38 / 62 = 61 % | > 85 % |
| Temps de rétablissement après échec CI | 18 min | < 30 min |

Les jobs s'exécutent en parallèle : le chemin critique est CodeQL Java (158 s) puis `buildx` (122 s), d'où ~2 min de bout en bout.

### Qualité (SonarCloud, projet `MikeDel88_microcrm`)

Source : analyses des pull requests.

| KPI | Valeur actuelle | Objectif |
|---|---|---|
| Couverture globale | 36,9 % (PR #23 et #24) | > 60 % à court terme, > 80 % sur le nouveau code |
| Quality gate PR | OK sur les PR récentes (#17 à #24) ; ERROR sur la PR #11 (couverture du nouveau code 25 %) | OK bloquant |
| Bugs / vulnérabilités / code smells (nouveau code) | 0 / 0 / 0 | 0 / 0 / 0 |
| Duplication (nouveau code) | 0,0 % | < 3 % |
| Security hotspots revus | 100 % | 100 % |

Le quality gate par défaut ne porte que sur le **nouveau code** ; la couverture globale de 36,9 % n'est donc pas bloquante aujourd'hui.

Constat : la CI n'analyse que les PR (les push sur `feature/**` et `fix/**` ne la déclenchent plus), donc l'analyse Sonar de `main` datait du 13/10 (commit d'init, avant la config de couverture) et affichait des chiffres périmés (21 bugs, 6 vulnérabilités, pas de couverture, quality gate `NONE`). À corriger si besoin : faire analyser `main` par un workflow.

### Exploitation (logs et supervision, via ELK)

| KPI | Source | Objectif |
|---|---|---|
| Fréquence des erreurs : nombre de logs `log.level: ERROR` par heure | Kibana, `filebeat-*`, conteneur `microcrm-back-1` | tendance stable ou à la baisse |
| Volume de logs par niveau (INFO/WARN/ERROR) | Kibana, dashboard logs | ERROR < 1 % du volume |
| Latence des requêtes HTTP (p95) | `metricbeat-*`, `http_server_requests_seconds` (actuator) | < 500 ms |
| Taux de réponses 5xx | access log Caddy (`status`) + actuator | < 1 % |
| CPU / mémoire des conteneurs | Metricbeat module `docker` | mémoire back < 80 % de la limite |

## 3. Recalculer les valeurs

Aucun outil à installer, l'API publique suffit (60 requêtes/heure sans jeton).

```bash
# Runs CI/CD (durées, succès, échecs)
curl -s "https://api.github.com/repos/MikeDel88/microcrm/actions/runs?per_page=100"
# Durée de chaque job d'un run
curl -s "https://api.github.com/repos/MikeDel88/microcrm/actions/runs/<run_id>/jobs"
# Lead time : created_at -> merged_at des PR fusionnées
curl -s "https://api.github.com/repos/MikeDel88/microcrm/pulls?state=closed&per_page=100"
# Qualité Sonar
curl -s "https://sonarcloud.io/api/measures/component?component=MikeDel88_microcrm&metricKeys=bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density"
curl -s "https://sonarcloud.io/api/qualitygates/project_status?projectKey=MikeDel88_microcrm"
```

Calcul : durée d'un run = `updated_at - run_started_at` ; taux de réussite = runs `success` / runs totaux du workflow `CI` ; MTTR = temps entre un run `failure` et le premier `success` suivant.

## 4. Suite recommandée
1. Après le prochain merge sur `main`, vérifier que Sonar affiche la couverture et le quality gate sur la branche principale.
2. Remonter la couverture (36,9 %) : tests des composants front et des contrôleurs back.
3. Rejouer ce relevé chaque semaine et suivre l'évolution plutôt que les valeurs absolues.
