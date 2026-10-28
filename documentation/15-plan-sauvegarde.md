# Plan de sauvegarde

Objectif : définir **quoi** sauvegarder dans MicroCRM, **à quelle fréquence** et **comment**, puis comment restaurer. Ce plan complète :
- le plan de sécurité ([05](05-plan-securite.md)) ;
- la supervision ([11](11-supervision-elk.md)) ;
- le plan de déploiement ([14](14-plan-deploiement.md)).

État au **28/10/2026**.

Principe retenu : la règle **3-2-1**. On garde **3** copies des données, sur **2** supports différents, dont **1** hors site, c'est-à-dire hors de GitHub et hors du serveur.

## 1. Plan de sauvegarde

| Données / configuration | Contenu | Fréquence | Méthode | Stockage | Rétention |
|---|---|---|---|---|---|
| **Pipeline as Code (runners)** | workflows `.github/workflows/*` (CI, CD, release), `Dockerfile`, `compose*.yml`, `misc/docker/Caddyfile`, configuration ELK (`elk/*`), `.releaserc.json`, `.trivyignore`, `.gitleaksignore` | **Tous les jours** | `git clone --mirror` du dépôt complet (branches, tags, historique), poussé vers un second dépôt. Les réglages GitHub hors git (protection de branche, liste des secrets, permissions) sont exportés en JSON par l'API GitHub | dépôt miroir chez un autre hébergeur, ou stockage objet chiffré | 30 sauvegardes quotidiennes + 12 mensuelles |
| **Données de la base** | personnes, organisations et leurs liens | **Toutes les nuits** | **dump** complet (`pg_dump` ou l'outil de la base retenue), compressé, chiffré et horodaté, puis contrôlé : le fichier n'est pas vide et se relit. **Monitoring** : succès, durée et taille de chaque dump suivis, alerte en cas d'échec ou de taille anormale | stockage objet hors du serveur de la base, chiffré | 7 quotidiennes + 4 hebdomadaires + 12 mensuelles |
| **Secrets** | `SONAR_TOKEN_BACK`, `SONAR_TOKEN_FRONT`, `RELEASE_TOKEN`, valeurs de `.env.elk` (`ELASTIC_PASSWORD`, `KIBANA_PASSWORD`, `ENCRYPTION_KEY`), futurs identifiants de la base | **À chaque modification**, et au moins **chaque semaine** | **gestionnaire de secrets** (HashiCorp Vault, ou un équivalent type Bitwarden / 1Password), qui sert de source de vérité. Sauvegarde par snapshot chiffré du coffre. Les secrets GitHub et le fichier `.env.elk` sont alimentés depuis le coffre, jamais l'inverse | coffre + snapshot chiffré hors site ; clé de déchiffrement conservée à part | 4 hebdomadaires + toutes les versions dans le coffre |
| **Artefacts** | images Docker `ghcr.io/mikedel88/microcrm-{back,front}:X.Y.Z`, `microcrm-X.Y.Z.jar`, `microcrm-front-X.Y.Z.zip`, `SHA256SUMS.txt` | **Chaque semaine** | copie des versions publiées vers un second registre (`skopeo copy` ou `docker buildx imagetools create`), et téléchargement des fichiers des releases GitHub. Vérification des digests des images et des sommes `SHA256SUMS.txt` | second registre de conteneurs + stockage objet | toutes les versions finales ; RC : 3 mois |

### Éléments déjà couverts ou exclus

| Élément | Décision | Justification |
|---|---|---|
| Tableau de bord Kibana | couvert par la sauvegarde du dépôt | exporté et versionné dans `elk/kibana/dahsboard-microcrm.ndjson` ([11](11-supervision-elk.md)) |
| Logs et métriques ELK | **non sauvegardés** | données de diagnostic, de courte durée et reconstituables. En production, un snapshot Elasticsearch hebdomadaire reste possible |
| Projets SonarQube Cloud | **non sauvegardés** | service hébergé ; une analyse se relance à tout moment depuis le dépôt |
| Artefacts de CI (`upload-artifact` : rapports de tests, couverture) | **non sauvegardés** | expirent au bout de 90 jours ; ils se reproduisent en relançant la CI sur le commit voulu |
| Runners | **non sauvegardés** | runners hébergés par GitHub : seule leur définition compte, et elle est dans les workflows |

## 2. Restauration

| Données / configuration | Comment restaurer | Perte maximale (RPO) | Délai de reprise (RTO) | Test de restauration |
|---|---|---|---|---|
| Pipeline as Code | pousser le miroir vers un nouveau dépôt, réappliquer les réglages GitHub exportés, recréer les secrets depuis le coffre | 24 h | 2 h | chaque trimestre : restauration dans un dépôt de test et lancement de la CI |
| Base de données | arrêter le back, recharger le dernier dump (`pg_restore` ou équivalent), redémarrer, lancer les tests de fumée de [14](14-plan-deploiement.md) §C | 24 h | 1 h | **chaque mois** : restauration sur une base de test et contrôle du nombre d'enregistrements |
| Secrets | restaurer le snapshot du coffre, puis repousser les valeurs dans GitHub et dans `.env.elk`. Si une fuite est suspectée, **régénérer** les jetons au lieu de les restaurer | 1 semaine (0 si le coffre est intact) | 1 h | chaque trimestre : restauration du snapshot dans un coffre de test |
| Artefacts | redéployer depuis le second registre : `docker compose` avec l'image copiée (même digest) ; ou reconstruire depuis le tag git par la CD | 1 semaine | 30 min | chaque trimestre : tirer une version depuis le second registre et comparer les digests |

**Ordre de reprise** après un sinistre complet : secrets → Pipeline as Code → artefacts → base de données. Sans les secrets, la CI ne peut pas tourner. Sans le pipeline et les artefacts, l'application ne peut pas être redéployée. La base vient en dernier, une fois l'application en place.

## 3. Surveillance des sauvegardes

Une sauvegarde qui échoue sans prévenir ne vaut rien. Chaque tâche planifiée doit donc :
- **signaler ses échecs** : ouverture ou commentaire d'une issue GitHub, sur le modèle de `publish-failure` dans `cd.yml`, ou alerte du planificateur ;
- **publier un résumé** à chaque exécution : date, taille, durée, empreinte ;
- **vérifier ce qu'elle produit** : fichier non vide, digest ou somme de contrôle identique à la source.

Pour la base, le monitoring du dump nocturne suit trois indicateurs : succès ou échec, durée, taille. Une taille qui chute brutalement est le signe d'une sauvegarde incomplète ou d'une perte de données.

## 4. État actuel et suite

| Élément | Aujourd'hui | À mettre en place |
|---|---|---|
| Pipeline as Code | historique complet sur GitHub et sur les postes de développement (2 copies, 1 seul hébergeur) | miroir quotidien hors GitHub ; export des réglages du dépôt |
| Base de données | **HSQLDB en mémoire** : aucune donnée persistante, le jeu de démonstration est recréé à chaque démarrage. Il n'y a rien à sauvegarder | dump nocturne et monitoring dès l'arrivée de la base persistante ([05](05-plan-securite.md), priorité 5) |
| Secrets | stockés dans les secrets GitHub (non relisibles) et dans un `.env.elk` local, non versionné | gestionnaire de secrets comme source de vérité, avec snapshot hebdomadaire |
| Artefacts | images GHCR et releases GitHub conservées sans expiration, mais chez un seul fournisseur | copie hebdomadaire vers un second registre et un stockage objet |
| Tableau de bord Kibana | versionné dans le dépôt | – |

La première étape est la base de données persistante. Le plan de sauvegarde n'a de sens pour les données que lorsqu'elles survivent à un redémarrage. Les trois autres lignes (pipeline, secrets, artefacts) peuvent être mises en place dès maintenant, par des workflows planifiés sur le modèle des scans prévus dans le plan de sécurité.
