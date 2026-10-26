# Pipeline CI (GitHub Actions)

Objectif : automatiser le build du back et du front, l'exécution des tests existants et l'analyse qualité et sécurité avec SonarQube Cloud. Le pipeline applique les choix des documents [04-plan-testing-periodique.md](04-plan-testing-periodique.md) et [05-plan-securite.md](05-plan-securite.md).

Fichier : `.github/workflows/ci.yml`

## Enchaînement des jobs

```
back  ──┐
        ├──► sonar ──► ci-ok
front ──┘
```

`back` et `front` tournent en parallèle. `sonar` récupère ensuite leurs rapports pour importer la couverture. `ci-ok` agrège les résultats des trois jobs.

## Déclencheurs

| Événement | But |
|-----------|-----|
| Pull request vers `develop` ou `main` | Valider le code avant la fusion |
| Push sur `main` (après fusion) | Tenir à jour l'analyse SonarQube Cloud de la branche principale |
| Lancement manuel (`workflow_dispatch`) | Relancer le pipeline à la demande |

Un nouveau push sur la même branche annule le run précédent encore en cours.

## Jobs

| Job | Ce qu'il fait | Résultat produit |
|-----|---------------|------------------|
| `back` | `./gradlew build` : compilation, tests JUnit, couverture JaCoCo, Checkstyle, JAR | Rapport de tests « Tests back (JUnit) », artefacts `back-reports` et `back-jar` |
| `front` | `npm ci`, `npm run test:ci` (Karma, Chrome headless, couverture), `npm run build` | Rapport de tests « Tests front (Karma) », artefacts `front-coverage` et `front-dist` |
| `sonar` | Analyse SonarQube Cloud du back (plugin Gradle) et du front (scanner) avec import de la couverture ; attend le quality gate | Analyse et quality gate dans SonarQube Cloud |
| `ci-ok` | Échoue si un des jobs précédents a échoué ou a été annulé | Statut unique de validation |

## Où lire les résultats

- **Sur la pull request** : le statut de chaque job, et `ci-ok` qui bloque la fusion s'il est rouge.
- **Onglet *Checks*** : les rapports « Tests back (JUnit) » et « Tests front (Karma) » détaillent les tests réussis et échoués, avec les messages d'erreur.
- **Page du run (*Summary*)** : le résumé des tests et les **artefacts** téléchargeables :
  - rapports HTML des tests et de JaCoCo ;
  - rapport Checkstyle ;
  - couverture du front ;
  - JAR et build Angular.
- **SonarQube Cloud** : vulnérabilités, security hotspots, bugs, code smells, couverture et duplication, avec l'historique. Le quality gate est aussi affiché sur la PR.

## Bonnes pratiques appliquées

- **Moindre privilège** : `contents: read` par défaut, et `checks: write` uniquement pour publier les rapports de tests.
- **Secrets** : les tokens `SONAR_TOKEN_BACK` et `SONAR_TOKEN_FRONT` sont stockés dans les secrets du dépôt et ne sont injectés que dans le job `sonar`.
- **Reproductibilité** : `npm ci` (lockfile), wrapper Gradle, versions de Java et Node fixées, versions des actions figées.
- **Performance** : caches Gradle et npm, jobs en parallèle.
- **Tests exécutés une seule fois** : le job `sonar` réutilise les rapports au lieu de relancer les tests.

## Prérequis

1. Créer deux projets dans SonarQube Cloud (back et front) et désactiver l'*Automatic Analysis*.
2. Ajouter les secrets `SONAR_TOKEN_BACK` et `SONAR_TOKEN_FRONT` dans *Settings > Secrets and variables > Actions*.
3. Protéger `develop` et `main` : fusion par PR uniquement, avec `ci-ok` comme check obligatoire.

## Lancer les mêmes contrôles en local

```shell
cd back && ./gradlew build        # rapports dans back/build/reports
cd front && npm run test:ci       # couverture dans front/coverage, JUnit dans front/test-results
cd front && npm run build
```
