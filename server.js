const express = require('express');
const mysql   = require('mysql2');
const bcrypt  = require('bcrypt');
const cors    = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

const db = mysql.createConnection({
    host:     process.env.DB_HOST     || 'localhost',
    user:     process.env.DB_USER     || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME     || 'mental_health_db'
});

db.connect(err => {
    if (err) console.error('DB connection failed:', err.message);
    else     console.log('Connected to MySQL!');
});

const query = (sql, params) => new Promise((resolve, reject) => {
    db.query(sql, params, (err, results) => err ? reject(err) : resolve(results));
});

// REGISTER
app.post('/api/register', async (req, res) => {
    try {
        const { username, email, password } = req.body;
        if (!username || !email || !password) return res.status(400).json({ error: 'All fields required' });
        if (username.length < 3) return res.status(400).json({ error: 'Username must be at least 3 characters' });
        const hash = await bcrypt.hash(password, 10);
        const result = await query('INSERT INTO User (username, email, password_hash, role) VALUES (?, ?, ?, "user")', [username, email, hash]);
        await query('CALL AddPoints(?, 5, "Welcome bonus")', [result.insertId]);
        res.json({ message: 'Account created!', userId: result.insertId });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') return res.status(400).json({ error: 'Username or email already exists' });
        res.status(500).json({ error: err.message });
    }
});

// LOGIN
app.post('/api/login', async (req, res) => {
    try {
        const { username, password } = req.body;
        const rows = await query('SELECT * FROM User WHERE username = ?', [username]);
        if (!rows.length) return res.status(401).json({ error: 'User not found' });
        const user = rows[0];
        const match = await bcrypt.compare(password, user.password_hash);
        if (!match) return res.status(401).json({ error: 'Wrong password' });
        res.json({ message: 'Login successful', user: { user_id: user.user_id, username: user.username, role: user.role, total_points: user.total_points } });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// MOOD
app.post('/api/mood', async (req, res) => {
    try {
        const { user_id, mood_score, notes } = req.body;
        if (mood_score < 1 || mood_score > 5) return res.status(400).json({ error: 'Mood score must be between 1 and 5' });
        await query('INSERT INTO MoodEntry (user_id, mood_score, notes) VALUES (?, ?, ?)', [user_id, mood_score, notes || null]);
        await query('CALL AddPoints(?, 5, "Mood log")', [user_id]);
        res.json({ message: 'Mood logged! +5 points' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/mood/:userId', async (req, res) => {
    try {
        const rows = await query('SELECT * FROM MoodEntry WHERE user_id = ? ORDER BY logged_at DESC LIMIT 30', [req.params.userId]);
        res.json(rows);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/mood/:moodId', async (req, res) => {
    try {
        await query('DELETE FROM MoodEntry WHERE mood_id = ?', [req.params.moodId]);
        res.json({ message: 'Entry deleted' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// SLEEP
app.post('/api/sleep', async (req, res) => {
    try {
        const { user_id, hours_slept, quality_score } = req.body;
        if (hours_slept < 0 || hours_slept > 24) return res.status(400).json({ error: 'Hours must be between 0 and 24' });
        if (quality_score < 1 || quality_score > 5) return res.status(400).json({ error: 'Quality must be 1-5' });
        await query('INSERT INTO SleepLog (user_id, hours_slept, quality_score) VALUES (?, ?, ?)', [user_id, hours_slept, quality_score]);
        await query('CALL AddPoints(?, 5, "Sleep log")', [user_id]);
        res.json({ message: 'Sleep logged! +5 points' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/sleep/:userId', async (req, res) => {
    try {
        const rows = await query('SELECT * FROM SleepLog WHERE user_id = ? ORDER BY logged_at DESC LIMIT 30', [req.params.userId]);
        res.json(rows);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/sleep/:sleepId', async (req, res) => {
    try {
        await query('DELETE FROM SleepLog WHERE sleep_id = ?', [req.params.sleepId]);
        res.json({ message: 'Entry deleted' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// JOURNAL
app.post('/api/journal', async (req, res) => {
    try {
        const { user_id, content } = req.body;
        if (!content || !content.trim()) return res.status(400).json({ error: 'Content cannot be empty' });
        await query('INSERT INTO Journal (user_id, content) VALUES (?, ?)', [user_id, content]);
        await query('CALL AddPoints(?, 10, "Journal entry")', [user_id]);
        res.json({ message: 'Journal saved! +10 points' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/journal/:userId', async (req, res) => {
    try {
        const rows = await query('SELECT * FROM Journal WHERE user_id = ? ORDER BY created_at DESC', [req.params.userId]);
        res.json(rows);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/journal/:journalId', async (req, res) => {
    try {
        await query('DELETE FROM Journal WHERE journal_id = ?', [req.params.journalId]);
        res.json({ message: 'Entry deleted' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// CHECKLIST
const TASKS = ['Exercise','Drink Water','Meditate','Go Outside','Social Interaction'];

app.get('/api/checklist/:userId', async (req, res) => {
    try {
        const today = new Date().toISOString().split('T')[0];
        let existing = await query('SELECT * FROM Checklist WHERE user_id = ? AND date = ?', [req.params.userId, today]);
        if (existing.length === 0) {
            for (const task of TASKS) {
                await query('INSERT INTO Checklist (user_id, task_name, completed, date) VALUES (?, ?, FALSE, ?)', [req.params.userId, task, today]);
            }
            existing = await query('SELECT * FROM Checklist WHERE user_id = ? AND date = ?', [req.params.userId, today]);
        }
        res.json(existing);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.put('/api/checklist/:checklistId', async (req, res) => {
    try {
        const { completed, user_id } = req.body;
        await query('UPDATE Checklist SET completed = ? WHERE checklist_id = ?', [completed, req.params.checklistId]);
        if (completed) await query('CALL AddPoints(?, 3, "Checklist completion")', [user_id]);
        res.json({ message: completed ? 'Task done! +3 points' : 'Task unchecked' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// BADGES
app.get('/api/badges/:userId', async (req, res) => {
    try {
        const rows = await query(`
            SELECT b.*, CASE WHEN ub.user_id IS NOT NULL THEN 1 ELSE 0 END AS earned, ub.earned_at
            FROM Badge b LEFT JOIN UserBadge ub ON b.badge_id = ub.badge_id AND ub.user_id = ?
            ORDER BY b.badge_id`, [req.params.userId]);
        res.json(rows);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// ANALYTICS
app.get('/api/analytics/:userId', async (req, res) => {
    try {
        const uid = req.params.userId;
        const moodData  = await query(`SELECT DATE(logged_at) as date, ROUND(AVG(mood_score),1) as avg_mood FROM MoodEntry WHERE user_id = ? AND logged_at >= NOW() - INTERVAL 7 DAY GROUP BY DATE(logged_at) ORDER BY date ASC`, [uid]);
        const sleepData = await query(`SELECT DATE(logged_at) as date, ROUND(AVG(hours_slept),1) as avg_sleep FROM SleepLog WHERE user_id = ? AND logged_at >= NOW() - INTERVAL 7 DAY GROUP BY DATE(logged_at) ORDER BY date ASC`, [uid]);
        const stats = await query(`SELECT
            (SELECT ROUND(AVG(mood_score),1) FROM MoodEntry WHERE user_id = ? AND logged_at >= NOW() - INTERVAL 7 DAY) AS avg_mood,
            (SELECT ROUND(AVG(hours_slept),1) FROM SleepLog WHERE user_id = ? AND logged_at >= NOW() - INTERVAL 7 DAY) AS avg_sleep,
            (SELECT COUNT(*) FROM MoodEntry WHERE user_id = ? AND logged_at >= NOW() - INTERVAL 7 DAY) AS mood_count,
            (SELECT COUNT(*) FROM Journal WHERE user_id = ? AND created_at >= NOW() - INTERVAL 7 DAY) AS journal_count,
            (SELECT COUNT(*) FROM Checklist WHERE user_id = ? AND completed = TRUE AND date >= CURDATE() - INTERVAL 7 DAY) AS checklist_done,
            (SELECT COUNT(*) FROM Checklist WHERE user_id = ? AND date >= CURDATE() - INTERVAL 7 DAY) AS checklist_total`,
            [uid, uid, uid, uid, uid, uid]);
        res.json({ moodData, sleepData, stats: stats[0] });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// LEADERBOARD
app.get('/api/leaderboard', async (req, res) => {
    try {
        const rows = await query('SELECT * FROM Leaderboard');
        res.json(rows);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// PROFILE
app.get('/api/profile/:userId', async (req, res) => {
    try {
        const rows = await query('SELECT * FROM UserWellnessSummary WHERE user_id = ?', [req.params.userId]);
        res.json(rows[0]);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// ADMIN - all users
app.get('/api/admin/users', async (req, res) => {
    try {
        const rows = await query('SELECT * FROM UserWellnessSummary WHERE role = "user" ORDER BY total_points DESC');
        res.json(rows);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// ADMIN - combined analytics
app.get('/api/admin/analytics', async (req, res) => {
    try {
        const overview = await query(`SELECT
            (SELECT COUNT(*) FROM User WHERE role='user') AS total_users,
            (SELECT ROUND(AVG(mood_score),1) FROM MoodEntry WHERE logged_at >= NOW()-INTERVAL 7 DAY) AS avg_mood_week,
            (SELECT ROUND(AVG(hours_slept),1) FROM SleepLog WHERE logged_at >= NOW()-INTERVAL 7 DAY) AS avg_sleep_week,
            (SELECT COUNT(*) FROM MoodEntry WHERE logged_at >= NOW()-INTERVAL 7 DAY) AS mood_logs_week,
            (SELECT COUNT(*) FROM Journal WHERE created_at >= NOW()-INTERVAL 7 DAY) AS journals_week,
            (SELECT COUNT(*) FROM Checklist WHERE completed=TRUE AND date >= CURDATE()-INTERVAL 7 DAY) AS checklist_done_week`);
        const correlation = await query(`SELECT
            CASE WHEN s.hours_slept>=8 THEN 'Great (8+ hrs)' WHEN s.hours_slept>=6 THEN 'Okay (6-8 hrs)' ELSE 'Poor (<6 hrs)' END AS sleep_category,
            ROUND(AVG(m.mood_score),2) AS avg_mood, COUNT(*) AS entries
            FROM SleepLog s JOIN MoodEntry m ON s.user_id=m.user_id AND DATE(s.logged_at)=DATE(m.logged_at)
            GROUP BY sleep_category ORDER BY avg_mood DESC`);
        const activities = await query(`SELECT task_name, COUNT(*) AS total, SUM(completed) AS done,
            ROUND(SUM(completed)/COUNT(*)*100,0) AS rate FROM Checklist GROUP BY task_name ORDER BY rate DESC`);
        const weeklyUsers = await query('SELECT * FROM WeeklyAnalytics');
        res.json({ overview: overview[0], correlation, activities, weeklyUsers });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// ADMIN - inactive users
app.get('/api/admin/inactive', async (req, res) => {
    try {
        const rows = await query(`SELECT u.user_id, u.username, u.email, u.total_points,
            MAX(m.logged_at) AS last_activity, DATEDIFF(NOW(), MAX(m.logged_at)) AS days_inactive
            FROM User u LEFT JOIN MoodEntry m ON u.user_id=m.user_id WHERE u.role='user'
            GROUP BY u.user_id HAVING days_inactive >= 3 OR last_activity IS NULL ORDER BY days_inactive DESC`);
        res.json(rows);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// ADMIN - single user detail
app.get('/api/admin/user/:userId', async (req, res) => {
    try {
        const uid = req.params.userId;
        const [user, moods, sleeps, journals, badges] = await Promise.all([
            query('SELECT * FROM UserWellnessSummary WHERE user_id = ?', [uid]),
            query('SELECT * FROM MoodEntry WHERE user_id = ? ORDER BY logged_at DESC LIMIT 10', [uid]),
            query('SELECT * FROM SleepLog WHERE user_id = ? ORDER BY logged_at DESC LIMIT 10', [uid]),
            query('SELECT * FROM Journal WHERE user_id = ? ORDER BY created_at DESC LIMIT 5', [uid]),
            query('SELECT b.*, CASE WHEN ub.user_id IS NOT NULL THEN 1 ELSE 0 END AS earned FROM Badge b LEFT JOIN UserBadge ub ON b.badge_id=ub.badge_id AND ub.user_id=?', [uid])
        ]);
        res.json({ user: user[0], moods, sleeps, journals, badges });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running at http://localhost:${PORT}`));
