-- Runs once, on first initialisation of an empty Postgres data directory.
--
-- Section 4: one instance, schema-per-service. Keycloak is the exception - it gets its own
-- database rather than a schema, because it owns and migrates its tables itself and must never be
-- touched by an application Flyway run.

CREATE DATABASE keycloak;

\connect delivery

-- Required by the tracking schema for geography columns and geo-queries (Section 4).
CREATE EXTENSION IF NOT EXISTS postgis;
-- UUID generation for outbox rows and entity ids.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Trigram indexes for product name/description search in the catalog (Phase 1).
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- One schema per service. Logically isolated, operationally one instance to run and back up.
--
-- NOTE: the brief (Section 4) names the order schema "order". That is a reserved SQL word, which
-- would force double-quoting in every query, migration and Hibernate mapping that touches it. It
-- is named "orders" here instead. This is the one deliberate deviation from the brief's data model
-- and it is cosmetic - no table, column or relationship differs.
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS product;
CREATE SCHEMA IF NOT EXISTS orders;
CREATE SCHEMA IF NOT EXISTS tracking;
CREATE SCHEMA IF NOT EXISTS notification;
CREATE SCHEMA IF NOT EXISTS files;
CREATE SCHEMA IF NOT EXISTS accounting;
CREATE SCHEMA IF NOT EXISTS settings;
CREATE SCHEMA IF NOT EXISTS transfer;
-- The Core Banking Simulator's own storage (Phase 4). Not part of the platform's data model: it
-- stands in for a system OUTSIDE the platform, and giving it a schema the platform's services can
-- read would let a test assert against the bank's internals instead of through its API. Dev only -
-- in staging and production nothing owns this schema because the simulator is not deployed.
CREATE SCHEMA IF NOT EXISTS corebanking;
-- The WhatsApp front door: conversations, their messages, and the drafts a merchant turns into
-- orders. Holds no order data of its own — placing one goes through Order Manager.
CREATE SCHEMA IF NOT EXISTS whatsapp;
-- Applications to join the platform, and the Camunda engine that walks them through review.
-- The engine's own ACT_* tables live here too: they are this service's working state, not a
-- separate system, and giving them their own schema would only mean a second grant to maintain.
CREATE SCHEMA IF NOT EXISTS onboarding;
