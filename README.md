# TP 2 individuel — Construire un pipeline structuré avec PokeAPI, n8n et PostgreSQL

## 1. Structure SQL des tables

Voici les requêtes utilisées pour créer l'architecture de la base de données :

```sql
CREATE TABLE IF NOT EXISTS ingestion_runs (
    run_id SERIAL PRIMARY KEY,
    source TEXT,
    started_at TIMESTAMP,
    finished_at TIMESTAMP,
    status TEXT,
    records_received INT,
    records_inserted INT
);

CREATE TABLE IF NOT EXISTS pokemon (
    id SERIAL PRIMARY KEY,
    pokemon_id INT,
    pokemon_name TEXT,
    base_experience INT,
    height INT,
    weight INT,
    main_type TEXT,
    has_official_artwork BOOLEAN,
    has_front_sprite BOOLEAN,
    source_last_updated_at TIMESTAMP,
    ingested_at TIMESTAMP DEFAULT NOW(),
    run_id INT REFERENCES ingestion_runs(run_id)
);
```

## 2. Description du workflow n8n

Le workflow suit une logique d'ETL (Extract, Transform, Load) complète :
1. **Initialisation (Load / Pre-task)** : Un trigger manuel lance l'exécution. Le flux crée/tronque les tables et insère immédiatement une nouvelle ligne dans `ingestion_runs` avec le statut `running` pour obtenir un `run_id`.
2. **Extraction (Extract)** : Une requête HTTP `GET https://pokeapi.co/api/v2/pokemon?limit=10` récupère la liste des 10 premiers Pokémon. Un nœud de code JavaScript découpe ensuite le tableau `results` de l'API en éléments individuels pour l'itération.
3. **Boucle d'enrichissement (Loop)** : Pour chaque élément (Pokémon), une seconde requête HTTP est faire pour chercher le détail de ses statistiques.
4. **Transformation (Transform)** : Un nœud de code extrait les attributs utiles depuis le JSON parfois très imbriqué de l'API, gère les valeurs manquantes de manière sécurisée (avec des `|| null` ou `|| 0`), et crée des indicateurs booléens exploitables (`has_official_artwork`, `has_front_sprite`).
5. **Insertion (Load)** : Chaque Pokémon proprement reformaté est inséré via SQL dans PostgreSQL dans la table `pokemon`, correctement associé au `run_id` de l'exécution en cours.
6. **Mise à jour du statut** : À la fin de la boucle, un "Merge" permet de terminer et le statut de la table `ingestion_runs` est mis à jour (`status = 'success'`), avec la date de fin et le décompte (`records_inserted = 10`).
7. **Contrôles Finaux** : Plusieurs requêtes de vérification sont exécutées pour valider l'intégrité de la table `pokemon`.

## 3. Preuve de chargement dans PostgreSQL

_Note pour toi : Modifie cette ligne ou insère ici une capture d'écran du client de base de données (ex: DBeaver, pgAdmin) montrant les 10 lignes insérées dans la table `pokemon`._

*(Exemple de format Markdown pour image : `![Preuve DB](images/proof.png)`)*

## 4. Lien du repo GitHub

[🔗 Lien vers le dépôt GitHub](https://github.com/TODO) *(Pense à mettre ton lien!)*

## 5. Requêtes SQL de contrôle

Voici les 5 requêtes exécutées pour valider les données chargées :

```sql
-- 1. Nombre total de Pokémon chargés
SELECT COUNT(*) FROM pokemon;

-- 2. Nombre de Pokémon sans image officielle
SELECT COUNT(*) FROM pokemon WHERE has_official_artwork = false;

-- 3. Nombre de Pokémon sans sprite frontal
SELECT COUNT(*) FROM pokemon WHERE has_front_sprite = false;

-- 4. Répartition par type principal
SELECT main_type, COUNT(*) FROM pokemon GROUP BY main_type;

-- 5. Pokémon dont le nom est vide ou manquant
SELECT * FROM pokemon WHERE pokemon_name IS NULL OR pokemon_name = '';
```

## 6. Justification logique Data Warehouse

**Pourquoi l'architecture réalisée relève-t-elle d'une logique Data Warehouse ?**

L'architecture mise en place correspond à une démarche décisionnelle (type Entrepôt de Données) car :
1. **Séparation des finalités** : Les données sont extraites d'un système tiers / de production (l'API PokeAPI) pour être centralisées dans une base d'analyse distincte locale (PostgreSQL) conçue pour être requêtée.
2. **Phase de Transformation et modélisation (ETL)** : Les données brutes et fortement hiérarchisées (JSON complexe) sont nettoyées, aplaties, et enrichies avec de nouveaux axes d'analyses (ex. booléens de présence d'image `has_official_artwork`). Le format final relationnel permet aux analystes de faire de l'agrégation.
3. **Traçabilité et Métadonnées** : L'utilisation spécifique de la table `ingestion_runs` ainsi que des clés/timestamps comme `run_id`, `source` et `ingested_at` permet de tracer avec précision les différentes intégrations techniques (lignage de la donnée). Cette supervision de la qualité et des "batchs" est le cœur d'un pipeline Data Warehouse pérenne.
