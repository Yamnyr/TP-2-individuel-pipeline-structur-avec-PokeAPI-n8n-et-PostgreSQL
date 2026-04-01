# TP 3 — Restitution analytique et automatisation Discord

## Partie A — Couche analytique dans PostgreSQL

Les vues suivantes ont été créées dans le fichier `sql/analytical_views.sql` :

1. **vw_pokemon_completeness** : Associe chaque Pokémon à son niveau de complétude (Complet, Incomplet, Critique, Dégradé) selon la présence d'images et de fichiers S3 associés.
2. **vw_type_distribution** : Agrège le volume de Pokémon par type principal, et calcule le pourcentage de Pokémon ayant un artwork et la moyenne d'expérience de base.
3. **vw_global_kpi** : Synthétise le référentiel en donnant les comptages globaux (Total Pokémon, % de complétude global, etc.).

## Partie B — KPI pertinents retenus

1. **Nombre Total de Pokémon dans la Base** : Un indicateur de base pour connaître la profondeur actuelle du catalogue.
2. **Pourcentage de Complétude Globale (%)** : Permet de piloter la qualité d'enrichissement. Un catalogue comportant 100% de fiches avec images + data brutes (MinIO) est de bonne qualité.
3. **Volume de Pokémon critiques (sans aucune image)** : Ces fiches nécessitent une action technique ou d'enrichissement urgente car inexploitables pour l'affichage visuel ou client.
4. **Répartition de la présence d'image par Type (Top 3 types et Flop 3 types)** : Permet de cibler si un type particulier de Pokémon présente plus de problèmes de crawling ou d'API.

## Partie C — Restitution visuelle (Dashboarding)

**Description de la restitution visuelle :**
- **En-tête** : 3 grands KPI au format numérique : "Total Pokémon", "Qualité du Catalogue (%)", "Alertes Fiches Critiques".
- **Graphique en Anneau (Donut)** : Répartition des Pokémon selon leur état de qualité (Complet, Incomplet, Critique, Dégradé).
- **Graphique en Barres** : Top 10 des types avec leur pourcentage de Pokémon possédant un artwork.
- **Tableau de données (bas du dashboard)** : Liste des Pokémon classés en "Critique" avec leur ID, nom, et type, constituant un plan d'action immédiat.

## Partie D, E, F — Workflow n8n et Commandes Bot Discord

Commandes implémentées dans le bot Discord :
- `!kpi` : Interroge la vue `vw_global_kpi` et retourne un statut global synthétique de la base actuelle avec les principaux pourcentages.
- `!pokemon [nom]` : Recherche un Pokémon par son nom dans `vw_pokemon_completeness` et affiche son état de qualité (la présence d'image, le nombre de fichiers associés au data lake).
- `!incomplete` : Requête la liste des Pokémon "Critiques" (max 10 résultats) depuis `vw_pokemon_completeness` pour signaler lesquels nécessitent une intervention.

### Exemples de réponses retournées par le bot

**!kpi**
> **Dashboard Qualité du Référentiel**
> **Total Pokémon :** 150
> **Taux de Complétude :** 82.5%
> **Fiches Critiques :** 5 fiches nécessitent votre attention (sans images).
> **Fichiers dans le Datalake :** 284 fichiers stockés.

**!pokemon pikachu**
> **Pikachu**
> Type : electric
> Artwork : Présent | Sprite : Présent
> Fichiers S3 : 2 associés
> **Status :** Complet

**!incomplete**
> **Alerte : Fiches Pokémon Critiques**
> Voici les 3 premiers Pokémon sans aucune image :
> - #45 Vileplume (Type: grass)
> - #61 Poliwhirl (Type: water)
> - #98 Krabby (Type: water)

## Partie H — Réponse rédigée

**Pourquoi une couche analytique intermédiaire est utile ?**
La couche analytique transforme la donnée brute technique en une structure compréhensible et pré-calculée. Cela évite au système de visualisation ou au workflow n8n de rejouer des jointures complexes, garantissant la performance et l'homogénéité des calculs de KPIs.
Les KPI choisis traduisent techniquement une "fiche complétée", ciblant ce qui rend la donnée exploitable visuellement (les images). La restitution visuelle permet d’avoir une vue macro dynamique de la santé du catalogue (Dashboarding), tandis que le bot Discord offre une vue micro réactive : alerter (ex. `!incomplete`) ou interroger individuellement sans quitter son espace de travail, créant un système d'action direct à l'opposé de la requête SQL monolithique, statique et difficile d'accès pour les non-techniciens.
