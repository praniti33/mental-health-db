-- ============================================================
-- Mental Health Tracking and Analytics System
-- Database Schema
-- ============================================================
DROP DATABASE IF EXISTS mental_health_db;
CREATE DATABASE IF NOT EXISTS mental_health_db;
USE mental_health_db;

-- ── USERS ──────────────────────────────────────────────────
CREATE TABLE User (
    user_id      INT AUTO_INCREMENT PRIMARY KEY,
    username     VARCHAR(50) UNIQUE NOT NULL,
    email        VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role         ENUM('user', 'admin') DEFAULT 'user',
    total_points INT DEFAULT 0,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_username CHECK (LENGTH(username) >= 3),
    CONSTRAINT chk_email    CHECK (email LIKE '%@%.%'),
    CONSTRAINT chk_points   CHECK (total_points >= 0)
);

-- ── MOOD ENTRIES ───────────────────────────────────────────
CREATE TABLE MoodEntry (
    mood_id    INT AUTO_INCREMENT PRIMARY KEY,
    user_id    INT NOT NULL,
    mood_score INT NOT NULL,
    notes      TEXT,
    logged_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES User(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_mood CHECK (mood_score BETWEEN 1 AND 5)
);

-- ── SLEEP LOGS ─────────────────────────────────────────────
CREATE TABLE SleepLog (
    sleep_id      INT AUTO_INCREMENT PRIMARY KEY,
    user_id       INT NOT NULL,
    hours_slept   DECIMAL(4,2) NOT NULL,
    quality_score INT NOT NULL,
    logged_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES User(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_sleep   CHECK (hours_slept BETWEEN 0 AND 24),
    CONSTRAINT chk_quality CHECK (quality_score BETWEEN 1 AND 5)
);

-- ── JOURNAL ────────────────────────────────────────────────
CREATE TABLE Journal (
    journal_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id    INT NOT NULL,
    content    TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES User(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_journal_content CHECK (LENGTH(content) > 0)
);

-- ── CHECKLIST ──────────────────────────────────────────────
CREATE TABLE Checklist (
    checklist_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id      INT NOT NULL,
    task_name    VARCHAR(100) NOT NULL,
    completed    BOOLEAN DEFAULT FALSE,
    date         DATE NOT NULL DEFAULT (CURRENT_DATE),
    FOREIGN KEY (user_id) REFERENCES User(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_task CHECK (task_name IN ('Exercise','Drink Water','Meditate','Go Outside','Social Interaction'))
);

-- ── POINTS LOG ─────────────────────────────────────────────
CREATE TABLE Points (
    point_id   INT AUTO_INCREMENT PRIMARY KEY,
    user_id    INT NOT NULL,
    points     INT NOT NULL,
    reason     VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES User(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_points_val CHECK (points > 0)
);

-- ── BADGES ─────────────────────────────────────────────────
CREATE TABLE Badge (
    badge_id    INT AUTO_INCREMENT PRIMARY KEY,
    badge_name  VARCHAR(100) NOT NULL,
    description TEXT,
    icon        VARCHAR(10) DEFAULT '🏅'
);

-- ── USER BADGES ────────────────────────────────────────────
CREATE TABLE UserBadge (
    id        INT AUTO_INCREMENT PRIMARY KEY,
    user_id   INT NOT NULL,
    badge_id  INT NOT NULL,
    earned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id)  REFERENCES User(user_id) ON DELETE CASCADE,
    FOREIGN KEY (badge_id) REFERENCES Badge(badge_id) ON DELETE CASCADE,
    UNIQUE KEY unique_user_badge (user_id, badge_id)
);

-- ============================================================
-- VIEWS
-- ============================================================

-- User wellness summary view
CREATE VIEW UserWellnessSummary AS
SELECT
    u.user_id,
    u.username,
    u.email,
    u.role,
    u.total_points,
    u.created_at,
    ROUND(AVG(m.mood_score), 1)  AS avg_mood,
    ROUND(AVG(s.hours_slept), 1) AS avg_sleep,
    COUNT(DISTINCT m.mood_id)    AS total_mood_logs,
    COUNT(DISTINCT s.sleep_id)   AS total_sleep_logs,
    COUNT(DISTINCT j.journal_id) AS total_journals,
    COUNT(DISTINCT ub.badge_id)  AS badges_earned,
    MAX(m.logged_at)             AS last_mood_entry
FROM User u
LEFT JOIN MoodEntry m  ON u.user_id = m.user_id
LEFT JOIN SleepLog s   ON u.user_id = s.user_id
LEFT JOIN Journal j    ON u.user_id = j.user_id
LEFT JOIN UserBadge ub ON u.user_id = ub.user_id
GROUP BY u.user_id;

-- Weekly analytics view
CREATE VIEW WeeklyAnalytics AS
SELECT
    u.user_id,
    u.username,
    ROUND(AVG(CASE WHEN m.logged_at >= NOW() - INTERVAL 7 DAY THEN m.mood_score END), 1) AS weekly_avg_mood,
    ROUND(AVG(CASE WHEN s.logged_at >= NOW() - INTERVAL 7 DAY THEN s.hours_slept END), 1) AS weekly_avg_sleep,
    COUNT(DISTINCT CASE WHEN m.logged_at >= NOW() - INTERVAL 7 DAY THEN m.mood_id END) AS mood_entries_this_week,
    COUNT(DISTINCT CASE WHEN j.created_at >= NOW() - INTERVAL 7 DAY THEN j.journal_id END) AS journal_entries_this_week
FROM User u
LEFT JOIN MoodEntry m ON u.user_id = m.user_id
LEFT JOIN SleepLog s  ON u.user_id = s.user_id
LEFT JOIN Journal j   ON u.user_id = j.user_id
WHERE u.role = 'user'
GROUP BY u.user_id;

-- Leaderboard view
CREATE VIEW Leaderboard AS
SELECT
    u.user_id,
    u.username,
    u.total_points,
    COUNT(DISTINCT ub.badge_id) AS badges_earned,
    RANK() OVER (ORDER BY u.total_points DESC) AS ranking
FROM User u
LEFT JOIN UserBadge ub ON u.user_id = ub.user_id
WHERE u.role = 'user'
GROUP BY u.user_id
ORDER BY ranking;

-- ============================================================
-- STORED PROCEDURES
-- ============================================================

DELIMITER //

-- Award badges automatically based on user activity
CREATE PROCEDURE AwardBadges(IN p_user_id INT)
BEGIN
    DECLARE v_mood_count INT;
    DECLARE v_avg_mood   DECIMAL(3,1);
    DECLARE v_avg_sleep  DECIMAL(4,2);
    DECLARE v_streak     INT;

    -- Count total mood entries
    SELECT COUNT(*) INTO v_mood_count FROM MoodEntry WHERE user_id = p_user_id;

    -- Get average mood
    SELECT ROUND(AVG(mood_score),1) INTO v_avg_mood FROM MoodEntry WHERE user_id = p_user_id;

    -- Get average sleep
    SELECT ROUND(AVG(hours_slept),1) INTO v_avg_sleep FROM SleepLog WHERE user_id = p_user_id;

    -- Badge 1: Beginner - first entry
    IF v_mood_count >= 1 THEN
        INSERT IGNORE INTO UserBadge (user_id, badge_id) VALUES (p_user_id, 1);
    END IF;

    -- Badge 2: Consistent - 7+ entries (proxy for streak)
    IF v_mood_count >= 7 THEN
        INSERT IGNORE INTO UserBadge (user_id, badge_id) VALUES (p_user_id, 2);
    END IF;

    -- Badge 3: Dedicated - 30+ entries
    IF v_mood_count >= 30 THEN
        INSERT IGNORE INTO UserBadge (user_id, badge_id) VALUES (p_user_id, 3);
    END IF;

    -- Badge 4: Sleep Master - avg sleep > 7
    IF v_avg_sleep > 7 THEN
        INSERT IGNORE INTO UserBadge (user_id, badge_id) VALUES (p_user_id, 4);
    END IF;

    -- Badge 5: Positive Mind - avg mood > 4
    IF v_avg_mood > 4 THEN
        INSERT IGNORE INTO UserBadge (user_id, badge_id) VALUES (p_user_id, 5);
    END IF;
END //

-- Add points and log them
CREATE PROCEDURE AddPoints(IN p_user_id INT, IN p_points INT, IN p_reason VARCHAR(100))
BEGIN
    UPDATE User SET total_points = total_points + p_points WHERE user_id = p_user_id;
    INSERT INTO Points (user_id, points, reason) VALUES (p_user_id, p_points, p_reason);
    CALL AwardBadges(p_user_id);
END //

DELIMITER ;

-- ============================================================
-- TRIGGERS
-- ============================================================

DELIMITER //

-- Auto-award badges when points updated directly
CREATE TRIGGER after_points_update
AFTER UPDATE ON User
FOR EACH ROW
BEGIN
    IF NEW.total_points > OLD.total_points THEN
        CALL AwardBadges(NEW.user_id);
    END IF;
END //

DELIMITER ;

-- ============================================================
-- SEED DATA
-- ============================================================

-- Admin account (password: admin123)
INSERT INTO User (username, email, password_hash, role, total_points) VALUES
('admin', 'admin@mindbloom.com', '$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin', 0);

-- Sample users (password: password123)
INSERT INTO User (username, email, password_hash, role, total_points) VALUES
('priya_s',  'priya@example.com',  '$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'user', 185),
('arjun_m',  'arjun@example.com',  '$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'user', 120),
('sneha_r',  'sneha@example.com',  '$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'user', 310),
('rahul_k',  'rahul@example.com',  '$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'user', 95),
('meera_t',  'meera@example.com',  '$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'user', 240);

-- Badges
INSERT INTO Badge (badge_name, description, icon) VALUES
('Beginner',      'Logged your first entry',              '🥉'),
('Consistent',    'Logged mood for 7 days',               '🥈'),
('Dedicated',     'Made 30 total entries',                '🥇'),
('Sleep Master',  'Average sleep above 7 hours',          '😴'),
('Positive Mind', 'Average mood above 4',                 '😊');

-- Mood entries (1-5 scale, last 7 days)
INSERT INTO MoodEntry (user_id, mood_score, notes, logged_at) VALUES
(2,4,'Feeling good after walk!', NOW()-INTERVAL 6 DAY),
(2,3,'A bit stressed',           NOW()-INTERVAL 5 DAY),
(2,4,'Better today',             NOW()-INTERVAL 4 DAY),
(2,5,'Amazing day!',             NOW()-INTERVAL 3 DAY),
(2,3,'Tired today',              NOW()-INTERVAL 2 DAY),
(2,4,'Getting back on track',    NOW()-INTERVAL 1 DAY),
(2,4,'Feeling positive!',        NOW()),
(3,3,'Anxious about exams',      NOW()-INTERVAL 6 DAY),
(3,3,'Studied well',             NOW()-INTERVAL 5 DAY),
(3,2,'Overwhelmed',              NOW()-INTERVAL 4 DAY),
(3,4,'Friends helped',           NOW()-INTERVAL 3 DAY),
(3,4,'Great workout!',           NOW()-INTERVAL 2 DAY),
(3,4,'Calm and focused',         NOW()-INTERVAL 1 DAY),
(3,3,'Normal day',               NOW()),
(4,5,'Best day ever!',           NOW()-INTERVAL 6 DAY),
(4,4,'Productive',               NOW()-INTERVAL 5 DAY),
(4,5,'Meditated, felt amazing',  NOW()-INTERVAL 4 DAY),
(4,4,'Little tired',             NOW()-INTERVAL 3 DAY),
(4,4,'Good vibes',               NOW()-INTERVAL 2 DAY),
(4,5,'Loved today',              NOW()-INTERVAL 1 DAY),
(4,5,'Woke up refreshed',        NOW()),
(5,2,'Rough week',               NOW()-INTERVAL 6 DAY),
(5,3,'Feeling low',              NOW()-INTERVAL 5 DAY),
(5,3,'Better than yesterday',    NOW()-INTERVAL 4 DAY),
(5,3,'Miss home',                NOW()-INTERVAL 3 DAY),
(5,4,'Out with friends',         NOW()-INTERVAL 2 DAY),
(5,3,'Okay day',                 NOW()-INTERVAL 1 DAY),
(5,4,'Improving!',               NOW()),
(6,4,'Calm start',               NOW()-INTERVAL 6 DAY),
(6,4,'Yoga was refreshing',      NOW()-INTERVAL 5 DAY),
(6,3,'Headache but ok',          NOW()-INTERVAL 4 DAY),
(6,5,'Great news today!',        NOW()-INTERVAL 3 DAY),
(6,4,'Feeling grateful',         NOW()-INTERVAL 2 DAY),
(6,4,'Relaxed evening',          NOW()-INTERVAL 1 DAY),
(6,4,'Good morning energy',      NOW());

-- Sleep logs
INSERT INTO SleepLog (user_id, hours_slept, quality_score, logged_at) VALUES
(2,7.5,4,NOW()-INTERVAL 6 DAY),(2,6.0,3,NOW()-INTERVAL 5 DAY),(2,8.0,5,NOW()-INTERVAL 4 DAY),
(2,7.0,4,NOW()-INTERVAL 3 DAY),(2,5.5,2,NOW()-INTERVAL 2 DAY),(2,7.5,4,NOW()-INTERVAL 1 DAY),(2,8.0,5,NOW()),
(3,6.0,3,NOW()-INTERVAL 6 DAY),(3,7.0,4,NOW()-INTERVAL 5 DAY),(3,5.0,2,NOW()-INTERVAL 4 DAY),
(3,8.0,5,NOW()-INTERVAL 3 DAY),(3,7.5,4,NOW()-INTERVAL 2 DAY),(3,6.5,3,NOW()-INTERVAL 1 DAY),(3,7.0,4,NOW()),
(4,8.5,5,NOW()-INTERVAL 6 DAY),(4,8.0,5,NOW()-INTERVAL 5 DAY),(4,9.0,5,NOW()-INTERVAL 4 DAY),
(4,7.5,4,NOW()-INTERVAL 3 DAY),(4,8.0,4,NOW()-INTERVAL 2 DAY),(4,8.5,5,NOW()-INTERVAL 1 DAY),(4,8.0,5,NOW()),
(5,5.0,2,NOW()-INTERVAL 6 DAY),(5,6.0,3,NOW()-INTERVAL 5 DAY),(5,6.5,3,NOW()-INTERVAL 4 DAY),
(5,5.5,2,NOW()-INTERVAL 3 DAY),(5,7.0,4,NOW()-INTERVAL 2 DAY),(5,6.5,3,NOW()-INTERVAL 1 DAY),(5,7.0,4,NOW()),
(6,7.0,4,NOW()-INTERVAL 6 DAY),(6,7.5,4,NOW()-INTERVAL 5 DAY),(6,6.5,3,NOW()-INTERVAL 4 DAY),
(6,8.0,5,NOW()-INTERVAL 3 DAY),(6,7.5,4,NOW()-INTERVAL 2 DAY),(6,7.0,4,NOW()-INTERVAL 1 DAY),(6,7.5,5,NOW());

-- Journal entries
INSERT INTO Journal (user_id, content, created_at) VALUES
(2,'Today was a good day. Went for a walk and felt much better.',       NOW()-INTERVAL 5 DAY),
(2,'Feeling stressed about assignments but taking it one step at a time.',NOW()-INTERVAL 3 DAY),
(2,'Grateful for my friends today.',                                     NOW()-INTERVAL 1 DAY),
(3,'Exam pressure is real but I studied well today.',                    NOW()-INTERVAL 4 DAY),
(3,'Workout really helped clear my head.',                               NOW()-INTERVAL 2 DAY),
(4,'Meditation changed my morning completely. Highly recommend.',        NOW()-INTERVAL 5 DAY),
(4,'Best week in a while. Feeling on top of the world.',                NOW()-INTERVAL 2 DAY),
(5,'Missing home but trying to stay positive.',                         NOW()-INTERVAL 3 DAY),
(6,'Yoga session was so peaceful. Need to do this more often.',         NOW()-INTERVAL 4 DAY),
(6,'Got some great news today. So happy!',                              NOW()-INTERVAL 3 DAY);

-- Checklist entries
INSERT INTO Checklist (user_id, task_name, completed, date) VALUES
(2,'Exercise',          TRUE,  CURDATE()-INTERVAL 1 DAY),
(2,'Drink Water',       TRUE,  CURDATE()-INTERVAL 1 DAY),
(2,'Meditate',          FALSE, CURDATE()-INTERVAL 1 DAY),
(2,'Go Outside',        TRUE,  CURDATE()-INTERVAL 1 DAY),
(2,'Social Interaction',TRUE,  CURDATE()-INTERVAL 1 DAY),
(2,'Exercise',          TRUE,  CURDATE()),
(2,'Drink Water',       TRUE,  CURDATE()),
(2,'Meditate',          TRUE,  CURDATE()),
(2,'Go Outside',        FALSE, CURDATE()),
(2,'Social Interaction',TRUE,  CURDATE()),
(3,'Exercise',          TRUE,  CURDATE()-INTERVAL 1 DAY),
(3,'Drink Water',       TRUE,  CURDATE()-INTERVAL 1 DAY),
(3,'Meditate',          TRUE,  CURDATE()-INTERVAL 1 DAY),
(3,'Go Outside',        FALSE, CURDATE()-INTERVAL 1 DAY),
(3,'Social Interaction',FALSE, CURDATE()-INTERVAL 1 DAY),
(4,'Exercise',          TRUE,  CURDATE()),
(4,'Drink Water',       TRUE,  CURDATE()),
(4,'Meditate',          TRUE,  CURDATE()),
(4,'Go Outside',        TRUE,  CURDATE()),
(4,'Social Interaction',TRUE,  CURDATE()),
(5,'Drink Water',       TRUE,  CURDATE()),
(5,'Go Outside',        TRUE,  CURDATE()),
(6,'Exercise',          TRUE,  CURDATE()),
(6,'Meditate',          TRUE,  CURDATE()),
(6,'Drink Water',       TRUE,  CURDATE());

-- Points log
INSERT INTO Points (user_id, points, reason) VALUES
(2,5,'Mood log'),(2,5,'Sleep log'),(2,10,'Journal entry'),(2,3,'Checklist'),(2,5,'Mood log'),(2,5,'Sleep log'),
(3,5,'Mood log'),(3,5,'Sleep log'),(3,10,'Journal entry'),(3,3,'Checklist'),(3,5,'Mood log'),
(4,5,'Mood log'),(4,5,'Sleep log'),(4,10,'Journal entry'),(4,3,'Checklist'),(4,5,'Mood log'),(4,5,'Sleep log'),(4,10,'Journal entry'),
(5,5,'Mood log'),(5,5,'Sleep log'),(5,3,'Checklist'),(5,5,'Mood log'),
(6,5,'Mood log'),(6,5,'Sleep log'),(6,10,'Journal entry'),(6,3,'Checklist'),(6,5,'Mood log'),(6,5,'Sleep log'),(6,10,'Journal entry'),(6,3,'Checklist');

-- User badges (awarded based on activity)
INSERT INTO UserBadge (user_id, badge_id) VALUES
(2,1),(2,2),
(3,1),
(4,1),(4,2),(4,4),(4,5),
(5,1),
(6,1),(6,2),(6,4);
UPDATE User SET password_hash = '$2b$10$kdrl2eA1MZWqcloYxfOWZ.XeFL4uVgzMP159usT0jzxZmrrtE.QuW' WHERE username = 'admin';