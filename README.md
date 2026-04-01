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

[Preuve Image](image.png)


[Preuve Video](unknown_2026.03.31-12.39.mp4)


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

---

# TP Data Lake — Extension avec MinIO

## Partie A — Mise en place du stockage objet avec MinIO

### Ajout de MinIO dans Docker

Le service MinIO a été ajouté au fichier `docker-compose.yml` existant :

```yaml
minio:
  image: minio/minio
  container_name: minio_tp
  restart: always
  ports:
    - "9000:9000"
    - "9001:9001"
  environment:
    MINIO_ROOT_USER: minioadmin
    MINIO_ROOT_PASSWORD: minioadmin
  command: server /data --console-address ":9001"
  volumes:
    - minio_data:/data
```

- **Port 9000** : API S3 (utilisée par n8n pour envoyer des fichiers).
- **Port 9001** : Console Web MinIO (interface graphique).
- **Accès console** : `http://localhost:9001` — Login : `minioadmin` / `minioadmin`.

### Organisation logique du stockage

Un **bucket unique `pokemon-lake`** a été créé, avec des **préfixes logiques** pour organiser les fichiers :

| Préfixe              | Contenu                                      |
|----------------------|----------------------------------------------|
| `raw-pokemon/`       | Réponses JSON brutes de la PokéAPI           |
| `pokemon-images/`    | Images officielles / sprites des Pokémon     |
| `reports/`           | Rapports CSV ou JSON générés                 |

**Justification** : Un bucket unique avec des préfixes est plus simple à gérer (un seul jeu de permissions, une seule politique de rétention). Les préfixes logiques permettent malgré tout une séparation claire des données par nature, tout en restant flexibles pour de futurs ajouts.

### Preuve de démarrage de MinIO

_Insérer ici une capture d'écran de la console MinIO (`http://localhost:9001`) montrant le bucket `pokemon-lake` et ses préfixes._

### Preuve de création des buckets

_Insérer ici une capture d'écran montrant les dossiers `raw-pokemon/`, `pokemon-images/`, `reports/` dans le bucket._

---

## Partie B — Structure SQL enrichie

Les tables suivantes ont été ajoutées à PostgreSQL pour tracer les fichiers stockés dans MinIO :

```sql
CREATE TABLE IF NOT EXISTS pokemon_files (
    file_id SERIAL PRIMARY KEY,
    pokemon_id INT REFERENCES pokemon(pokemon_id),
    bucket_name TEXT NOT NULL,
    object_key TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_type TEXT,
    file_size INT,
    mime_type TEXT,
    minio_url TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS file_ingestion_log (
    log_id SERIAL PRIMARY KEY,
    file_name TEXT NOT NULL,
    bucket_name TEXT NOT NULL,
    object_key TEXT NOT NULL,
    source TEXT,
    status TEXT DEFAULT 'pending',
    file_size INT,
    mime_type TEXT,
    checksum TEXT,
    processed_at TIMESTAMP DEFAULT NOW()
);
```

### Colonnes supplémentaires ajoutées

| Colonne     | Table               | Justification                                                    |
|-------------|---------------------|------------------------------------------------------------------|
| `file_size` | les deux            | Permet de surveiller le volume de stockage consommé              |
| `mime_type` | les deux            | Identifie le type de contenu (application/json, image/png, etc.) |
| `minio_url` | `pokemon_files`    | Lien direct vers l'objet dans MinIO pour un accès rapide         |
| `checksum`  | `file_ingestion_log`| Assure l'intégrité du fichier (détection de corruption)          |

---

## Partie C — Description du workflow n8n (Data Lake)

Le workflow Data Lake se greffe sur le pipeline ETL existant et ajoute les étapes suivantes :

1. **Stockage du JSON brut** : Après l'appel de détail par Pokémon (`HTTP Request2`), la réponse JSON brute complète est envoyée dans MinIO via un nœud **S3** (compatible MinIO) dans le bucket `pokemon-lake` sous la clé `raw-pokemon/<pokemon_name>.json`.
2. **Enregistrement des métadonnées** : Un nœud SQL insère une ligne dans `pokemon_files` (liant le fichier au `pokemon_id`) et une ligne dans `file_ingestion_log` (traçant l'opération avec le statut, la taille, le type MIME).
3. **Stockage de l'image officielle** *(optionnel)* : Si le Pokémon possède un artwork officiel (`has_official_artwork = true`), son image est téléchargée et déposée dans MinIO sous `pokemon-images/<pokemon_name>.png`, avec enregistrement correspondant en base.

### Configuration des credentials S3 dans n8n

Pour connecter n8n à MinIO, un credential de type **S3** a été configuré :

| Paramètre        | Valeur        |
|-------------------|---------------|
| Access Key ID     | `minioadmin`  |
| Secret Access Key | `minioadmin`  |
| Region            | `us-east-1`   |
| Custom Endpoint   | `http://minio:9000` |
| Force Path Style  | `true`        |

### Preuve — Capture du workflow n8n

_Insérer ici une capture d'écran du workflow n8n montrant les nœuds S3 et les insertions SQL associées._

### Preuve — Exemple d'objet stocké dans MinIO

_Insérer ici une capture d'écran de la console MinIO montrant un fichier (ex: `raw-pokemon/bulbasaur.json`) stocké dans le bucket._

### Preuve — Enregistrement des métadonnées en base

_Insérer ici une capture d'écran du résultat d'un `SELECT * FROM pokemon_files LIMIT 5;` et/ou `SELECT * FROM file_ingestion_log LIMIT 5;`._

---

## Partie D — Pourquoi cette architecture relève d'une logique Data Lake / Lakehouse

L'ajout de MinIO transforme fondamentalement l'architecture en la rapprochant d'un modèle Data Lakehouse. MinIO apporte une couche de stockage objet compatible S3, complémentaire à PostgreSQL : là où la base relationnelle structure et indexe les données pour des requêtes analytiques rapides, MinIO conserve les fichiers bruts (JSON, images, rapports) dans leur format d'origine, sans transformation préalable. Cette conservation du « brut » est essentielle car elle permet de rejouer, retraiter ou réanalyser les données sources à tout moment, sans dépendre des choix de modélisation initiaux (approche « Schema-on-Read »). La base PostgreSQL ne stocke volontairement pas les fichiers eux-mêmes : elle agit comme un catalogue de métadonnées (Metastore) qui référence les objets via des clés (`object_key`, `bucket_name`), assurant ainsi la traçabilité et le lignage de chaque fichier ingéré. Cette séparation entre le stockage brut à bas coût et le moteur de requêtage structuré combine les avantages d'un Data Lake (flexibilité, scalabilité, conservation du brut) et ceux d'un Data Warehouse (requêtes ACID, traçabilité, gouvernance), formant une architecture Lakehouse bien plus riche et évolutive qu'une simple base relationnelle.
