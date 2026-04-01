-- Vue analytique détaillée de la complétude par Pokémon
CREATE OR REPLACE VIEW vw_pokemon_completeness AS
SELECT 
    p.pokemon_id,
    p.pokemon_name,
    p.main_type,
    p.has_official_artwork,
    p.has_front_sprite,
    (SELECT COUNT(*) FROM pokemon_files pf WHERE pf.pokemon_id = p.pokemon_id) AS file_count,
    CASE 
        WHEN p.has_official_artwork = true AND p.has_front_sprite = true AND (SELECT COUNT(*) FROM pokemon_files pf WHERE pf.pokemon_id = p.pokemon_id) > 0 THEN 'Complet'
        WHEN p.has_official_artwork = false AND p.has_front_sprite = false THEN 'Critique (Aucune image)'
        WHEN (SELECT COUNT(*) FROM pokemon_files pf WHERE pf.pokemon_id = p.pokemon_id) = 0 THEN 'Dégradé (Aucun fichier S3)'
        ELSE 'Incomplet'
    END AS quality_status
FROM 
    pokemon p;

-- Vue analytique de répartition par type (KPI)
CREATE OR REPLACE VIEW vw_type_distribution AS
SELECT 
    main_type,
    COUNT(*) AS total_pokemon,
    ROUND(SUM(CASE WHEN has_official_artwork = true THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_with_artwork,
    ROUND(AVG(base_experience), 2) AS avg_base_experience
FROM 
    pokemon
GROUP BY 
    main_type
ORDER BY 
    total_pokemon DESC;

-- Vue agrégée des KPIs globaux du référentiel
CREATE OR REPLACE VIEW vw_global_kpi AS
SELECT
    (SELECT COUNT(*) FROM pokemon) AS total_pokemon,
    (SELECT COUNT(*) FROM pokemon WHERE has_official_artwork = true) AS pokemon_with_artwork,
    (SELECT COUNT(*) FROM vw_pokemon_completeness WHERE quality_status = 'Complet') AS total_complet,
    (SELECT COUNT(*) FROM vw_pokemon_completeness WHERE quality_status LIKE 'Critique%') AS total_critique,
    ROUND((SELECT COUNT(*) FROM vw_pokemon_completeness WHERE quality_status = 'Complet') * 100.0 / NULLIF((SELECT COUNT(*) FROM pokemon), 0), 2) AS pct_completeness,
    (SELECT COUNT(*) FROM pokemon_files) AS total_files_in_datalake;
