# Principes de conteneurisation et de déploiement

Objectif : décrire le rôle du Dockerfile existant et celui de docker-compose, puis la stratégie envisagée pour publier les images et automatiser le déploiement.

## Rôle du Dockerfile existant

Le projet fournit un **Dockerfile multi-stage** unique à la racine du monorepo. Les étapes de **build** compilent le code. Les étapes d'**exécution** ne gardent que le résultat, ce qui donne des images finales plus légères et sans outils de compilation.

| Cible | Base | Rôle |
|-------|------|------|
| `front-build` | `node` | Installe les dépendances (`npm ci`) et compile l'application Angular |
| `back-build` | `gradle:jdk17` | Compile l'API Spring Boot et produit le JAR (`./gradlew build`) |
| `front` | `alpine` + Caddy | Sert la SPA sur les ports 80 et 443 ; `try_files` renvoie vers `index.html` pour le routage Angular |
| `back` | `alpine` + OpenJDK 21 | Lance le JAR de l'API |
| `standalone` | `alpine` + supervisord | Regroupe front et back dans un seul conteneur |

**Limites à corriger** (détail dans [03-contraintes-techniques-cicd.md](03-contraintes-techniques-cicd.md)) :
- versions des images de base non figées ;
- Java 21 au lieu de 17 ;
- port 4200 exposé au lieu de 8080 ;
- conteneurs exécutés en root ;
- tests relancés pendant le build de l'image ;
- deux processus dans l'image `standalone`.

## Rôle de docker-compose

Le projet n'a pas encore de fichier docker-compose. Il en faudra un pour :

- **Lancer front et back ensemble** avec une seule commande, en local comme en CI.
- **Centraliser la configuration** : ports, variables d'environnement (profil Spring, URL de l'API), healthchecks.
- **Ordonner le démarrage** : le front ne démarre que lorsque le back est *healthy*.
- **Servir au test de fumée en CI** : vérifier que les conteneurs démarrent et répondent.
- **Remplacer l'image `standalone`** : un service par conteneur.

Deux usages sont prévus :

| Fichier | Usage |
|---------|-------|
| Compose de **build** | Construit les images depuis les sources (développement, CI) |
| Compose de **release** | Tire les images publiées au tag voulu (déploiement), sans build |

## Stratégie de déploiement envisagée

**Publication des images**
- Une image par service (front, back), publiée dans le registre de conteneurs de GitHub.
- Tags immuables : SHA du commit et version SemVer (`X.Y.Z`). Les tags mobiles (`latest`) ne servent jamais au déploiement.
- Les images sont publiées uniquement si elles ont passé le scan de vulnérabilités.

**Versionnement**
- La version est calculée automatiquement à partir des messages de commits (*Conventional Commits*).
- Chaque release produit un tag git, une release GitHub et un changelog.

**Flux de livraison**

```
PR validée par la CI ──► fusion ──► build des images ──► scan ──► publication ──► release
```

**Déploiement automatisé**
- La **même image** passe d'un environnement à l'autre (dev, test, prod). Seule la configuration change : profil Spring, URL de l'API.
- L'environnement cible tire les images au tag voulu avec le compose de release, puis un healthcheck vérifie le démarrage.
- Retour arrière (*rollback*) : redéployer le tag précédent.

Mise en œuvre : [08 Conteneurisation](08-conteneurisation.md), [09 Déploiement](09-deploiement.md), [10 Release](10-release.md) ; plan de déploiement finalisé dans [14 Plan de déploiement](14-plan-deploiement.md).

## Principes retenus

- **Build once, deploy many** : un seul build, promu d'un environnement à l'autre.
- **Un service par conteneur**.
- **Images minimales, sans root, versions figées**.
- **Aucun secret dans les images** : tout passe par l'environnement d'exécution.
- **Rien n'est publié sans les tests et le scan de sécurité**.
