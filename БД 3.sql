-- 3.1. ПЕРВИЧНЫЙ КЛЮЧ + SEQUENCE
ALTER TABLE "Cirki".cirki_clubs
    ADD COLUMN id BIGSERIAL PRIMARY KEY;

-- 3.2. ОГРАНИЧЕНИЯ NOT NULL И UNIQUE

-- NOT NULL на ключевые бизнес-поля
ALTER TABLE "Cirki".cirki_clubs
    ALTER COLUMN "data.general.name"        SET NOT NULL,
    ALTER COLUMN "data.general.locale.name" SET NOT NULL;

-- UNIQUE по data.general.id 
ALTER TABLE "Cirki".cirki_clubs
    ADD CONSTRAINT cirki_clubs_general_id_unique
    UNIQUE ("data.general.id");


-- ============================================================
-- 3.3.1. ФИЛЬТРАЦИЯ ПО РЕГИОНУ
-- ============================================================
-- ВНИМАНИЕ: в текущем наборе данных нет цирков Вологодской области!
-- Если запустить DELETE, таблица полностью очистится.
-- Поэтому этот блок ЗАКОММЕНТИРОВАН, чтобы сохранить данные для проверки.
--
-- DELETE FROM "Cirki".cirki_clubs
-- WHERE "data.general.address.fullAddress" NOT ILIKE '%Вологодская%'
--    OR "data.general.address.fullAddress" IS NULL;

-- Проверка количества записей
SELECT COUNT(*) AS total_cirki FROM "Cirki".cirki_clubs;


-- 3.3.2. POSTGIS + КОЛОНКА geom
CREATE EXTENSION IF NOT EXISTS postgis;

ALTER TABLE "Cirki".cirki_clubs
    ADD COLUMN geom geometry(Point, 4326);


-- 3.3.3–3.3.4. ПРЕОБРАЗОВАНИЕ mapPosition → geom
UPDATE "Cirki".cirki_clubs
SET geom = ST_SetSRID(
        ST_GeomFromGeoJSON("data.general.address.mapPosition"::text),
        4326
    )
WHERE "data.general.address.mapPosition" IS NOT NULL
  AND "data.general.address.mapPosition" ? 'coordinates';

-- Контроль заполнения геометрии
SELECT
    COUNT(*) FILTER (WHERE geom IS NOT NULL) AS with_geom,
    COUNT(*) FILTER (WHERE geom IS NULL)     AS without_geom
FROM "Cirki".cirki_clubs;


-- 3.3.5. ТАБЛИЦА tags
DROP TABLE IF EXISTS "Cirki".m2m_cirki_clubs_tags;
DROP TABLE IF EXISTS "Cirki".tags;

CREATE TABLE "Cirki".tags (
    id         BIGSERIAL PRIMARY KEY,
    name       VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT now()
);


-- 3.3.6. ЗАПОЛНЕНИЕ tags ИЗ JSONB
INSERT INTO "Cirki".tags (name)
SELECT DISTINCT (elem->>'name') AS tag_name
FROM "Cirki".cirki_clubs,
     LATERAL jsonb_array_elements("data.general.tags") AS elem
WHERE "data.general.tags" IS NOT NULL
  AND jsonb_typeof("data.general.tags") = 'array'
  AND jsonb_typeof(elem) = 'object'
  AND (elem->>'name') IS NOT NULL
  AND (elem->>'name') <> '';

-- Проверка: теги должны быть чистыми (например, "Для детей", "Искусство")
SELECT * FROM "Cirki".tags ORDER BY name LIMIT 20;


-- 3.3.7. ПРОМЕЖУТОЧНАЯ ТАБЛИЦА m2m_cirki_clubs_tags
CREATE TABLE "Cirki".m2m_cirki_clubs_tags (
    cirki_club_id BIGINT NOT NULL
        REFERENCES "Cirki".cirki_clubs(id) ON DELETE CASCADE,
    tag_id        BIGINT NOT NULL
        REFERENCES "Cirki".tags(id)        ON DELETE CASCADE,
    PRIMARY KEY (cirki_club_id, tag_id)
);

-- Заполняем связями «цирк ↔ тег»
INSERT INTO "Cirki".m2m_cirki_clubs_tags (cirki_club_id, tag_id)
SELECT DISTINCT c.id, t.id
FROM "Cirki".cirki_clubs c,
     LATERAL jsonb_array_elements(c."data.general.tags") AS elem
JOIN "Cirki".tags t ON t.name = (elem->>'name')
WHERE c."data.general.tags" IS NOT NULL
  AND jsonb_typeof(c."data.general.tags") = 'array'
  AND (elem->>'name') IS NOT NULL;

-- Проверка связей
SELECT COUNT(*) AS links FROM "Cirki".m2m_cirki_clubs_tags;

-- 3.3.8. ИНДЕКСЫ
CREATE INDEX idx_m2m_cirki_club_id ON "Cirki".m2m_cirki_clubs_tags (cirki_club_id);
CREATE INDEX idx_m2m_tag_id        ON "Cirki".m2m_cirki_clubs_tags (tag_id);

CREATE INDEX idx_cirki_clubs_geom  ON "Cirki".cirki_clubs USING GIST (geom);
CREATE INDEX idx_cirki_clubs_tags  ON "Cirki".cirki_clubs USING GIN ("data.general.tags");


-- ФИНАЛЬНАЯ ПРОВЕРКА
SELECT
    (SELECT COUNT(*) FROM "Cirki".cirki_clubs)          AS cirki,
    (SELECT COUNT(*) FROM "Cirki".tags)                 AS tags,
    (SELECT COUNT(*) FROM "Cirki".m2m_cirki_clubs_tags) AS links;

SELECT t.name, COUNT(*) AS cnt
FROM "Cirki".tags t
JOIN "Cirki".m2m_cirki_clubs_tags m ON m.tag_id = t.id
GROUP BY t.name
ORDER BY cnt DESC
LIMIT 10;