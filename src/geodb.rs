use anyhow::{Context, Result};
use flate2::read::GzDecoder;
use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;

const DB_FILENAME: &str = "dbip-city-lite.mmdb";

/// Returns the platform-specific data directory for maperick.
/// e.g. ~/.local/share/maperick on Linux, ~/Library/Application Support/maperick on macOS
pub fn data_dir() -> Result<PathBuf> {
    let base = dirs::data_dir().context("Could not determine system data directory")?;
    Ok(base.join("maperick"))
}

/// Returns the expected path to the GeoIP database file.
pub fn default_db_path() -> Result<PathBuf> {
    Ok(data_dir()?.join(DB_FILENAME))
}

/// Ensures the GeoIP database exists, downloading it if necessary.
/// If `explicit_path` is provided and non-empty, uses that instead.
/// Returns the resolved path to the database file.
pub fn ensure_db(explicit_path: Option<&str>) -> Result<PathBuf> {
    // If user gave an explicit path, just use it (and verify it exists)
    if let Some(path) = explicit_path {
        if !path.is_empty() {
            let p = PathBuf::from(path);
            if p.exists() {
                return Ok(p);
            }
            anyhow::bail!(
                "GeoIP database not found at '{}'. Remove the -p flag to auto-download.",
                path
            );
        }
    }

    // Check the standard data directory
    let db_path = default_db_path()?;
    if db_path.exists() {
        return Ok(db_path);
    }

    // Database not found — download it
    download_db(&db_path)?;
    Ok(db_path)
}

/// Downloads the DB-IP City Lite database (gzipped) and extracts it.
fn download_db(dest: &PathBuf) -> Result<()> {
    // Build the URL for the current month's database
    let now = chrono_free_date();
    let url = format!(
        "https://download.db-ip.com/free/dbip-city-lite-{}-{:02}.mmdb.gz",
        now.0, now.1
    );

    eprintln!("GeoIP database not found. Downloading...");
    eprintln!("  Source: {}", url);

    // Ensure the data directory exists
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create directory '{}'", parent.display()))?;
    }

    // Download
    let response = ureq::get(&url)
        .call()
        .with_context(|| format!("Failed to download GeoIP database from {}", url))?;

    let mut body = Vec::new();
    response
        .into_body()
        .as_reader()
        .read_to_end(&mut body)
        .context("Failed to read download response")?;

    // Decompress gzip
    let mut decoder = GzDecoder::new(&body[..]);
    let mut mmdb_data = Vec::new();
    decoder
        .read_to_end(&mut mmdb_data)
        .context("Failed to decompress GeoIP database")?;

    // Write to file
    let mut file = fs::File::create(dest)
        .with_context(|| format!("Failed to create file '{}'", dest.display()))?;
    file.write_all(&mmdb_data)
        .with_context(|| format!("Failed to write GeoIP database to '{}'", dest.display()))?;

    let size_mb = mmdb_data.len() as f64 / (1024.0 * 1024.0);
    eprintln!(
        "  Downloaded {:.1} MB to {}",
        size_mb,
        dest.display()
    );
    eprintln!("  Database provided by DB-IP (https://db-ip.com), CC-BY-4.0 license.");
    eprintln!();

    Ok(())
}

/// Returns (year, month) without pulling in the chrono crate.
/// Uses std::time::SystemTime.
fn chrono_free_date() -> (i32, u32) {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    // Simple calculation: days since epoch
    let days = (secs / 86400) as i64;
    // Approximate year and month from days since 1970-01-01
    // This is a simplified calculation, good enough for building a URL
    let mut y = 1970i32;
    let mut remaining = days;
    loop {
        let days_in_year = if is_leap(y) { 366 } else { 365 };
        if remaining < days_in_year {
            break;
        }
        remaining -= days_in_year;
        y += 1;
    }
    let months_days: [i64; 12] = if is_leap(y) {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    } else {
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    };
    let mut m = 1u32;
    for &d in &months_days {
        if remaining < d {
            break;
        }
        remaining -= d;
        m += 1;
    }
    (y, m)
}

fn is_leap(year: i32) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_data_dir_is_valid() {
        let dir = data_dir();
        assert!(dir.is_ok());
        let dir = dir.unwrap();
        assert!(dir.to_string_lossy().contains("maperick"));
    }

    #[test]
    fn test_default_db_path_contains_filename() {
        let path = default_db_path().unwrap();
        assert!(path.to_string_lossy().contains(DB_FILENAME));
    }

    #[test]
    fn test_chrono_free_date_is_reasonable() {
        let (year, month) = chrono_free_date();
        assert!(year >= 2024);
        assert!((1..=12).contains(&month));
    }

    #[test]
    fn test_explicit_nonexistent_path_fails() {
        let result = ensure_db(Some("/nonexistent/path/to/db.mmdb"));
        assert!(result.is_err());
    }
}
