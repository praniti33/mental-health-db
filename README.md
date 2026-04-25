# MindBloom

![Node.js](https://img.shields.io/badge/Backend-Node.js-43853d)
![Express](https://img.shields.io/badge/Framework-Express.js-000000)
![MySQL](https://img.shields.io/badge/Database-MySQL-4479A1)
![Status](https://img.shields.io/badge/Status-Active-2ea44f)

A database-driven mental health tracking application designed to store and analyze user well-being data in a structured manner.

---

## Overview

MindLedger enables users to log and monitor key aspects of mental health, including mood, sleep, activities, and gratitude entries. The system uses a relational database to organize this data and supports querying for meaningful insights into behavioral patterns.

---

## Features

* User profile management
* Mood tracking
* Sleep logging
* Activity tracking
* Gratitude entries
* Badge-based engagement system
* Peer interaction through posts

---

## Tech Stack

* Backend: Node.js, Express.js
* Database: MySQL
* Tools: MySQL Workbench
* Deployment: Railway

---

## Database Design

### Core Entities

* Users
* Mood_Entries
* Sleep_Logs
* Activities
* Gratitude_Entries
* Badges
* Peer_Posts

### Design Principles

* Primary keys for unique identification
* Foreign keys for referential integrity
* Normalization up to Third Normal Form (3NF)

---

## Data Flow

User input is sent to the backend via API calls. The backend validates and processes the request, executes SQL queries, and stores the data in the MySQL database. Data is retrieved and returned to the user as required.

---

## Sample Queries

```sql
SELECT * FROM mood_entries;

SELECT u.name, m.mood
FROM users u
JOIN mood_entries m
ON u.user_id = m.user_id;

SELECT mood, COUNT(*)
FROM mood_entries
GROUP BY mood;
```



This project was developed as part of a Database Systems Lab mini project.




