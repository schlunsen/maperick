use anyhow::{Context, Result};
use rusqlite::{params, Connection};
use std::collections::HashSet;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::app::Server;

/// How many ticks between DB flushes (~5 seconds at 250ms tick rate)
const FLUSH_INTERVAL: u32 = 20;

/// All-time stats for a single IP, loaded from the DB
pub struct AllTimeStats {
    pub first_seen: u64,
    pub last_seen: u64,
    pub times_detected: u64,
    pub total_connections: u64,
    pub location: String,
    pub country: String,
    pub all_ports: Vec<u16>,
    pub all_processes: Vec<String>,
}

/// Pending changes for a single IP, accumulated between flushes
struct PendingEntry {
    times_detected: u64,
    total_connections: u64,
    first_seen: u64,
    last_seen: u64,
    location: String,
    country: String,
    ports: HashSet<u16>,
    processes: HashSet<String>,
}

pub struct HistoryDb {
    db: Connection,
    pending: std::collections::HashMap<String, PendingEntry>,
    ticks_since_flush: u32,
}

impl HistoryDb {
    /// Open or create the history database in the maperick data dir.
    pub fn new() -> Result<Self> {
        let db_path = Self::db_path()?;

        // Ensure directory exists
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let db = Connection::open(&db_path)
            .with_context(|| format!("Failed to open history DB at {}", db_path.display()))?;

        // WAL mode for better performance, don't fsync on every write
        db.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")?;

        db.execute_batch(
            "CREATE TABLE IF NOT EXISTS connections (
                ip              TEXT PRIMARY KEY,
                location        TEXT NOT NULL DEFAULT '',
                country         TEXT NOT NULL DEFAULT '',
                first_seen      INTEGER NOT NULL,
                last_seen       INTEGER NOT NULL,
                times_detected  INTEGER NOT NULL DEFAULT 0,
                total_connections INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS seen_ports (
                ip   TEXT NOT NULL,
                port INTEGER NOT NULL,
                PRIMARY KEY (ip, port)
            );
            CREATE TABLE IF NOT EXISTS seen_processes (
                ip   TEXT NOT NULL,
                name TEXT NOT NULL,
                PRIMARY KEY (ip, name)
            );",
        )?;

        Ok(HistoryDb {
            db,
            pending: std::collections::HashMap::new(),
            ticks_since_flush: 0,
        })
    }

    fn db_path() -> Result<PathBuf> {
        let dir = crate::geodb::data_dir()?;
        Ok(dir.join("history.db"))
    }

    /// Record a tick's worth of server data into the pending buffer.
    /// Flushes to SQLite every FLUSH_INTERVAL ticks.
    pub fn record_tick(&mut self, servers: &[Server]) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        for server in servers {
            let entry = self
                .pending
                .entry(server.name.clone())
                .or_insert_with(|| PendingEntry {
                    times_detected: 0,
                    total_connections: 0,
                    first_seen: now,
                    last_seen: now,
                    location: String::new(),
                    country: String::new(),
                    ports: HashSet::new(),
                    processes: HashSet::new(),
                });

            entry.times_detected += 1;
            entry.total_connections += server.count as u64;
            entry.last_seen = now;
            entry.location.clone_from(&server.location);
            entry.country.clone_from(&server.country);
            entry.ports.extend(&server.ports);
            entry.processes.extend(server.processes.iter().cloned());
        }

        self.ticks_since_flush += 1;
        if self.ticks_since_flush >= FLUSH_INTERVAL {
            if let Err(e) = self.flush() {
                eprintln!("Warning: failed to flush history: {}", e);
            }
        }
    }

    /// Flush all pending data to SQLite in a single transaction, then clear pending.
    pub fn flush(&mut self) -> Result<()> {
        if self.pending.is_empty() {
            self.ticks_since_flush = 0;
            return Ok(());
        }

        let tx = self.db.transaction()?;

        for (ip, entry) in &self.pending {
            // UPSERT connection stats
            tx.execute(
                "INSERT INTO connections (ip, location, country, first_seen, last_seen, times_detected, total_connections)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                 ON CONFLICT(ip) DO UPDATE SET
                   location = ?2,
                   country = ?3,
                   first_seen = MIN(connections.first_seen, ?4),
                   last_seen = MAX(connections.last_seen, ?5),
                   times_detected = connections.times_detected + ?6,
                   total_connections = connections.total_connections + ?7",
                params![
                    ip,
                    entry.location,
                    entry.country,
                    entry.first_seen,
                    entry.last_seen,
                    entry.times_detected,
                    entry.total_connections,
                ],
            )?;

            // INSERT OR IGNORE ports
            for port in &entry.ports {
                tx.execute(
                    "INSERT OR IGNORE INTO seen_ports (ip, port) VALUES (?1, ?2)",
                    params![ip, port],
                )?;
            }

            // INSERT OR IGNORE processes
            for proc_name in &entry.processes {
                tx.execute(
                    "INSERT OR IGNORE INTO seen_processes (ip, name) VALUES (?1, ?2)",
                    params![ip, proc_name],
                )?;
            }
        }

        tx.commit()?;

        // Clear pending counters (not the whole map — keep entries for fast re-insert)
        self.pending.clear();
        self.ticks_since_flush = 0;

        Ok(())
    }

    /// Query all-time stats for a single IP from the database.
    pub fn get_alltime_stats(&self, ip: &str) -> Option<AllTimeStats> {
        let row = self
            .db
            .query_row(
                "SELECT first_seen, last_seen, times_detected, total_connections, location, country
                 FROM connections WHERE ip = ?1",
                params![ip],
                |row| {
                    Ok(AllTimeStats {
                        first_seen: row.get(0)?,
                        last_seen: row.get(1)?,
                        times_detected: row.get(2)?,
                        total_connections: row.get(3)?,
                        location: row.get(4)?,
                        country: row.get(5)?,
                        all_ports: vec![],
                        all_processes: vec![],
                    })
                },
            )
            .ok()?;

        // Get ports
        let mut ports: Vec<u16> = vec![];
        if let Ok(mut stmt) = self
            .db
            .prepare("SELECT port FROM seen_ports WHERE ip = ?1 ORDER BY port")
        {
            if let Ok(rows) = stmt.query_map(params![ip], |row| row.get(0)) {
                for port in rows.flatten() {
                    ports.push(port);
                }
            }
        }

        // Get processes
        let mut processes: Vec<String> = vec![];
        if let Ok(mut stmt) = self
            .db
            .prepare("SELECT name FROM seen_processes WHERE ip = ?1 ORDER BY name")
        {
            if let Ok(rows) = stmt.query_map(params![ip], |row| row.get(0)) {
                for name in rows.flatten() {
                    processes.push(name);
                }
            }
        }

        Some(AllTimeStats {
            all_ports: ports,
            all_processes: processes,
            ..row
        })
    }

    /// Get total number of unique IPs ever seen.
    pub fn total_unique_ips(&self) -> u64 {
        self.db
            .query_row("SELECT COUNT(*) FROM connections", [], |row| row.get(0))
            .unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_db() -> HistoryDb {
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;").unwrap();
        db.execute_batch(
            "CREATE TABLE IF NOT EXISTS connections (
                ip TEXT PRIMARY KEY, location TEXT NOT NULL DEFAULT '',
                country TEXT NOT NULL DEFAULT '', first_seen INTEGER NOT NULL,
                last_seen INTEGER NOT NULL, times_detected INTEGER NOT NULL DEFAULT 0,
                total_connections INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS seen_ports (
                ip TEXT NOT NULL, port INTEGER NOT NULL, PRIMARY KEY (ip, port)
            );
            CREATE TABLE IF NOT EXISTS seen_processes (
                ip TEXT NOT NULL, name TEXT NOT NULL, PRIMARY KEY (ip, name)
            );",
        )
        .unwrap();
        HistoryDb {
            db,
            pending: std::collections::HashMap::new(),
            ticks_since_flush: 0,
        }
    }

    #[test]
    fn test_record_and_flush() {
        let mut hist = make_test_db();
        let servers = vec![Server {
            name: "1.2.3.4".into(),
            location: "Berlin".into(),
            country: "Germany".into(),
            coords: (52.5, 13.4),
            count: 3,
            ports: vec![443, 80],
            processes: vec!["firefox".into()],
        }];

        hist.record_tick(&servers);
        hist.record_tick(&servers);
        assert!(hist.flush().is_ok());

        let stats = hist.get_alltime_stats("1.2.3.4").unwrap();
        assert_eq!(stats.times_detected, 2);
        assert_eq!(stats.total_connections, 6);
        assert_eq!(stats.location, "Berlin");
        assert_eq!(stats.all_ports, vec![80, 443]);
        assert_eq!(stats.all_processes, vec!["firefox"]);
    }

    #[test]
    fn test_multiple_flushes_accumulate() {
        let mut hist = make_test_db();
        let servers = vec![Server {
            name: "5.6.7.8".into(),
            location: "Tokyo".into(),
            country: "Japan".into(),
            coords: (35.7, 139.7),
            count: 1,
            ports: vec![22],
            processes: vec!["ssh".into()],
        }];

        hist.record_tick(&servers);
        hist.flush().unwrap();

        hist.record_tick(&servers);
        hist.flush().unwrap();

        let stats = hist.get_alltime_stats("5.6.7.8").unwrap();
        assert_eq!(stats.times_detected, 2); // accumulated across flushes
        assert_eq!(stats.total_connections, 2);
    }

    #[test]
    fn test_unknown_ip_returns_none() {
        let hist = make_test_db();
        assert!(hist.get_alltime_stats("9.9.9.9").is_none());
    }

    #[test]
    fn test_total_unique_ips() {
        let mut hist = make_test_db();
        let servers = vec![
            Server {
                name: "1.1.1.1".into(),
                location: "".into(),
                country: "".into(),
                coords: (0.0, 0.0),
                count: 1,
                ports: vec![],
                processes: vec![],
            },
            Server {
                name: "8.8.8.8".into(),
                location: "".into(),
                country: "".into(),
                coords: (0.0, 0.0),
                count: 1,
                ports: vec![],
                processes: vec![],
            },
        ];
        hist.record_tick(&servers);
        hist.flush().unwrap();
        assert_eq!(hist.total_unique_ips(), 2);
    }
}
